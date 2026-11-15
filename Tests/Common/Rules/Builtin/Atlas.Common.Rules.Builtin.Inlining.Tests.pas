unit Atlas.Common.Rules.Builtin.Inlining.Tests;

// Tests der Regel inline-not-expanded (#1017): fehlende Unit (H2443) bei
// Aufruf, Property-Getter und for-in, die korrigierte Form und eine nicht
// eingebettete Routine schweigen; strict private schweigt (#1383), inline-Aufrufer mit
// Unit nur im implementation-uses (H2445), direkter und indirekter Zyklus
// (H2456, H2457); Schnellkorrektur; abschaltbar; die Verweise im Index;
// Laufzeit bei vielen Aufrufen und langer uses-Kette (#1220); H2445 auch
// bei inline-Routinen, deren Rumpf auf nichts außerhalb verweist (#1381).
// Fehlalarme aus der Prüfung von Atlas und der RTL: Alias einer Deklaration
// aus System (tkRecord in System.TypInfo, TList<T>.Add), Zyklus bei Rümpfen
// nur mit eingebauten Typen und Intrinsics (THashFNV1a32.GetHashValue).
// Routinen aus System und SysInit (TMonitor.Enter, Pos) und direkt gerufene
// Mitglieder generischer Typen (TObjectList<T>[I]) brauchen keinen Eintrag im
// uses, auch gegen die RTL der Delphi-Installation (BDS).
// lsp-ignore an einem Aufruf, den der Index nicht kennt, bleibt ohne
// unused-suppression (RenameFile unter Linux).

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
    procedure IndexedAndSetProperties;
    /// <summary>#2309: Unit der Routine über einen geerbten Getter, inline-Mitglied einer generischen Instanz,
    /// Feld einer Instanz ohne Bedarf und Alias als Ergebnistyp.</summary>
    [Test]
    procedure OwnUnitInstanceMembersAndResultAlias;
    /// <summary>System und SysInit stehen implizit im uses: TMonitor.Enter, Pos und UpCase brauchen keinen
    /// Eintrag, auch wenn ihr Rumpf Verweise hat.</summary>
    [Test]
    procedure ImplicitSystemNeedsNoUses;
    /// <summary>Mitglied eines generischen Typs direkt gerufen (FListe[I] auf ein TObjectList&lt;T&gt;-Feld einer
    /// anderen Unit): Delphi 13 bettet ohne System.Generics.Collections ein.</summary>
    [Test]
    procedure GenericMemberNeedsNoUses;
    /// <summary>Gegen die RTL der Delphi-Installation (BDS; ohne sie übersprungen): TMonitor.Enter, Pos, UpCase und
    /// TObjectList&lt;T&gt;[I] auf ein Feld einer anderen Unit schweigen ohne System bzw.
    /// System.Generics.Collections im uses.</summary>
    [Test]
    procedure RealRtlNeedsNoImplicitOrGenericUnit;
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
    [Test]
    procedure UnknownCallKeepsSuppression;
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
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Inlining,
  Atlas.Common.Semantics.InlineCallees,
  Atlas.Tests.RuleAssert;

const
  // Count über einen inline-Getter mit Verweis (wie TList<T>.GetCount bis Delphi 12): Ein Feld einer Instanz
  // (FWerte: TListe<Integer>) braucht Werk.Listen erst über ihn (#2309).
  cUnitListen =
    'unit Werk.Listen;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TListe<T> = class'#10 +
    '  private'#10 +
    '    FDaten: TArray<T>;'#10 +
    '    function GetAnzahl: Integer; inline;'#10 +
    '  public'#10 +
    '    property Count: Integer read GetAnzahl;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TListe<T>.GetAnzahl: Integer;'#10 +
    'begin'#10 +
    '  Result := Length(FDaten);'#10 +
    'end;'#10 +
    'end.';

  // Fälle aus dem Delphi-13-Bau (#2309): TCollection.GetCount (Feld einer generischen Instanz, Count liest ein
  // Feld), TJSONArray.GetValue (Default-Property der Instanz mit inline-Getter), TFont.GetStyle (Alias als
  // Ergebnistyp).
  cUnitGenerisch =
    'unit Werk.Generisch;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFolge<T> = class'#10 +
    '  private'#10 +
    '    FAnzahl: NativeInt;'#10 +
    '    FDaten: TArray<T>;'#10 +
    '    function GetItem(I: NativeInt): T; inline;'#10 +
    '  public'#10 +
    '    property Count: NativeInt read FAnzahl;'#10 +
    '    property Items[I: NativeInt]: T read GetItem; default;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TFolge<T>.GetItem(I: NativeInt): T;'#10 +
    'begin'#10 +
    '  Result := FDaten[I];'#10 +
    'end;'#10 +
    'end.';

  cUnitSammlung =
    'unit Werk.Sammlung;'#10 +
    'interface'#10 +
    'uses Werk.Generisch;'#10 +
    'type'#10 +
    '  TEintrag = class'#10 +
    '  end;'#10 +
    '  TSammlung = class'#10 +
    '  private'#10 +
    '    FItems: TFolge<TEintrag>;'#10 +
    '    function GetCount: Integer; inline;'#10 +
    '    function GetEintrag(I: Integer): TEintrag; inline;'#10 +
    '  public'#10 +
    '    property Count: Integer read GetCount;'#10 +
    '    property Eintraege[I: Integer]: TEintrag read GetEintrag; default;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TSammlung.GetCount: Integer;'#10 +
    'begin'#10 +
    '  Result := FItems.Count;'#10 +
    'end;'#10 +
    'function TSammlung.GetEintrag(I: Integer): TEintrag;'#10 +
    'begin'#10 +
    '  Result := FItems[I];'#10 +
    'end;'#10 +
    'end.';

  cUnitTypen =
    'unit Werk.Typen;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TArt = (Fett, Kursiv);'#10 +
    '  TArten = set of TArt;'#10 +
    'implementation'#10 +
    'end.';

  cUnitSchrift =
    'unit Werk.Schrift;'#10 +
    'interface'#10 +
    'uses Werk.Typen;'#10 +
    'type'#10 +
    '  TArten = Werk.Typen.TArten;'#10 +
    '  TSchrift = class'#10 +
    '  private'#10 +
    '    FHoehe: Integer;'#10 +
    '    function GetArten: TArten; inline;'#10 +
    '    function GetHoehe: Integer; inline;'#10 +
    '  public'#10 +
    '    property Arten: TArten read GetArten;'#10 +
    '    property Hoehe: Integer read GetHoehe;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TSchrift.GetArten: TArten;'#10 +
    'begin'#10 +
    '  Result := [];'#10 +
    'end;'#10 +
    'function TSchrift.GetHoehe: Integer;'#10 +
    'begin'#10 +
    '  Result := FHoehe;'#10 +
    'end;'#10 +
    'end.';

  cUnitAnsicht =
    'unit Werk.Ansicht;'#10 +
    'interface'#10 +
    'uses Werk.Sammlung, Werk.Schrift;'#10 +
    'type'#10 +
    '  TSpalten = class(TSammlung)'#10 +
    '  end;'#10 +
    '  TAnsicht = class'#10 +
    '  public'#10 +
    '    Spalten: TSpalten;'#10 +
    '    Schrift: TSchrift;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitMathe =
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

  cUnitJson =
    'unit Werk.Json;'#10 +
    'interface'#10 +
    'uses Werk.Listen;'#10 +
    'type'#10 +
    '  TJsonEnum = class'#10 +
    '  public'#10 +
    '    constructor Create(AAnzahl: Integer);'#10 +
    '    function MoveNext: Boolean;'#10 +
    '  end;'#10 +
    '  TStil = (Fett, Kursiv);'#10 +
    '  TStile = set of TStil;'#10 +
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
    '    function GetWert(I: Integer): Integer; inline;'#10 +
    '    function GetStil: TStile; inline;'#10 +
    '    procedure SetStil(const AWert: TStile);'#10 +
    '    property Werte[I: Integer]: Integer read GetWert; default;'#10 +
    '    property Stil: TStile read GetStil write SetStil;'#10 +
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
    'function TJsonFeld.GetWert(I: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := FWerte.Count + I;'#10 +
    'end;'#10 +
    'function TJsonFeld.GetStil: TStile;'#10 +
    'begin'#10 +
    '  Result := [];'#10 +
    '  if FWerte.Count > 0 then'#10 +
    '    Include(Result, Fett);'#10 +
    'end;'#10 +
    'procedure TJsonFeld.SetStil(const AWert: TStile);'#10 +
    'begin'#10 +
    'end;'#10 +
    'function Doppelt(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := Mal2(A);'#10 +
    'end;'#10 +
    'end.';

  // Zyklus: Werk.Kreis verwendet Haupt, Werk.Ring über Werk.Kreis ebenso.
  cUnitKreis =
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

  cUnitRing =
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
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitListen, 'C:\P\Werk.Listen.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitMathe, 'C:\P\Werk.Mathe.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitJson, 'C:\P\Werk.Json.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitKreis, 'C:\P\Werk.Kreis.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitRing, 'C:\P\Werk.Ring.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitGenerisch, 'C:\P\Werk.Generisch.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitSammlung, 'C:\P\Werk.Sammlung.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitTypen, 'C:\P\Werk.Typen.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitSchrift, 'C:\P\Werk.Schrift.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitAnsicht, 'C:\P\Werk.Ansicht.pas', nil));
end;

function Haupt(const AUses, ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'uses ' + AUses + ';'#10'implementation'#10 +
    'procedure Lauf(F: TJsonFeld);'#10'var'#10'  X: Integer;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function Findings(const ASource: string; const AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, ASource, NewIndex, AConfig, 'Haupt.pas');
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := Findings(ASource, '');
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    Result := Result + Format('%d:%d %s|', [mFinding.Range.StartPos.Line, mFinding.Range.StartPos.Character,
      mFinding.Message]);
  end;
end;

{ TInliningRulesTests }

procedure TInliningRulesTests.MissingUnitIsReported;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Haupt('Werk.Json', '  X := F.Anzahl;'#10'  X := Doppelt(X);'#10));
  Assert.AreEqual('8:9 Inline-Funktion TJsonFeld.Anzahl wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|9:7 Inline-Funktion Doppelt wird nicht eingebettet: Werk.Mathe fehlt in uses (wie H2443).|',
    Messages(mFound));
  Assert.AreEqual(cInlineNotExpandedRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFound[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
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

procedure TInliningRulesTests.IndexedAndSetProperties;
begin
  // Getter hinter einer Index-Property, auch als default, nach as und über eine Mengen-Property (#1345).
  Assert.AreEqual('8:9 Inline-Funktion TJsonFeld.GetWert wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|9:8 Inline-Funktion TJsonFeld.GetWert wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|10:33 Inline-Funktion TJsonFeld.GetWert wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|11:14 Inline-Funktion TJsonFeld.GetStil wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|', Messages(Findings(Haupt('Werk.Json', '  X := F.Werte[0];'#10'  X := F[1];'#10 +
    '  X := (TObject(F) as TJsonFeld).Werte[2];'#10'  F.Stil := F.Stil + [Fett];'#10))));
  Assert.AreEqual('', Messages(Findings(Haupt('Werk.Json, Werk.Listen', '  X := F.Werte[0] + F[1];'#10 +
    '  F.Stil := F.Stil + [Fett];'#10))));
end;

procedure TInliningRulesTests.OwnUnitInstanceMembersAndResultAlias;
var
  mSource: string;
begin
  mSource := 'unit Haupt;'#10'interface'#10'uses Werk.Ansicht;'#10'implementation'#10 +
    'procedure Lauf(A: TAnsicht);'#10'var'#10'  X: Integer;'#10'begin'#10'  X := A.Spalten.Count;'#10 +
    '  if A.Spalten[X] = nil then'#10'    Exit;'#10'  if A.Schrift.Arten = [] then'#10'    X := A.Schrift.Hoehe;'#10 +
    'end;'#10'end.';
  // Count: nur die Unit der Routine (wie TCollection.GetCount ohne System.Classes); Spalten[X]: dazu die Unit
  // des inline-Getters der Instanz (wie TJSONArray.GetValue); Arten: die Unit hinter dem Alias (wie
  // TFont.GetStyle); Hoehe liest nur ein Feld.
  Assert.AreEqual('8:17 Inline-Funktion TSammlung.GetCount wird nicht eingebettet: Werk.Sammlung fehlt in uses ' +
    '(wie H2443).|9:14 Inline-Funktion TSammlung.GetEintrag wird nicht eingebettet: Werk.Generisch, Werk.Sammlung ' +
    'fehlen in uses (wie H2443).|11:15 Inline-Funktion TSchrift.GetArten wird nicht eingebettet: Werk.Typen fehlt ' +
    'in uses (wie H2443).|', Messages(Findings(mSource)));
  Assert.AreEqual('', Messages(Findings(StringReplace(mSource, 'uses Werk.Ansicht;',
    'uses Werk.Ansicht, Werk.Sammlung, Werk.Generisch, Werk.Typen;', []))));
end;

procedure TInliningRulesTests.ImplicitSystemNeedsNoUses;
const
  cSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TMonitor = record'#10 +
    '  private'#10 +
    '    class procedure Sperre(const AObjekt: TObject); static;'#10 +
    '  public'#10 +
    '    class procedure Enter(const AObjekt: TObject); static; inline;'#10 +
    '  end;'#10 +
    'function Pos(const ATeil, AText: string): Integer; inline;'#10 +
    'implementation'#10 +
    'function PosIntern(const ATeil, AText: string): Integer;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'class procedure TMonitor.Sperre(const AObjekt: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'class procedure TMonitor.Enter(const AObjekt: TObject);'#10 +
    'begin'#10 +
    '  if Kennung > 0 then'#10 +
    '    Sperre(AObjekt);'#10 +
    'end;'#10 +
    'function Pos(const ATeil, AText: string): Integer;'#10 +
    'begin'#10 +
    '  Result := PosIntern(ATeil, AText) + Kennung;'#10 +
    'end;'#10 +
    'end.';
  cSysInit =
    'unit SysInit;'#10 +
    'interface'#10 +
    'function Kennung: Integer; inline;'#10 +
    'implementation'#10 +
    'function Intern: Integer;'#10 +
    'begin'#10 +
    '  Result := 1;'#10 +
    'end;'#10 +
    'function Kennung: Integer;'#10 +
    'begin'#10 +
    '  Result := Intern + Pos(''a'', ''b'');'#10 +
    'end;'#10 +
    'end.';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Werk.Mathe;'#10 +
    'procedure Lauf(O: TObject);'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  TMonitor.Enter(O);'#10 +
    '  System.TMonitor.Enter(O);'#10 +
    '  X := Pos(''='', ''a=b'') + Kennung + Halb(2);'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
  mRefs: string;
  mSymbol: TIndexSymbol;
begin
  mIndex := NewIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cSystem, 'C:\P\System.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cSysInit, 'C:\P\SysInit.pas', nil));
  // Die Rümpfe haben Verweise (wie in der RTL, hier auf die jeweils andere implizite Unit): Ohne die Ausnahme
  // verlangte die Regel System bzw. SysInit im uses.
  mRefs := '';
  for mSymbol in TIndexExtractor.ExtractText(cSystem, 'C:\P\System.pas', nil).Symbols do
  begin
    if mSymbol.InlineRefs <> nil then
    begin
      mRefs := mRefs + mSymbol.QualifiedName + '=' + String.Join(',', mSymbol.InlineRefs) + '|';
    end;
  end;
  Assert.AreEqual('TMonitor.Enter=Kennung|Pos=Kennung|TMonitor.Enter=Kennung|Pos=Kennung|', mRefs);
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, mIndex, '',
    'Haupt.pas')));
end;

procedure TInliningRulesTests.GenericMemberNeedsNoUses;
const
  cHalter =
    'unit Werk.Halter;'#10 +
    'interface'#10 +
    'uses Werk.Generisch;'#10 +
    'type'#10 +
    '  THalter = class'#10 +
    '  public'#10 +
    '    Liste: TFolge<Integer>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Werk.Halter;'#10 +
    'procedure Lauf(H: THalter);'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  X := H.Liste[0] + H.Liste.Items[1];'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := NewIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cHalter, 'C:\P\Werk.Halter.pas', nil));
  // Vorher: „Werk.Generisch fehlt in uses“ für TFolge.GetItem. Aus dem Rumpf einer Routine einer anderen Unit
  // heraus braucht das Mitglied seine Unit weiter (OwnUnitInstanceMembersAndResultAlias, Spalten[X]).
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, mIndex, '',
    'Haupt.pas')));
end;

/// <summary>Ordner source\rtl der Delphi-Installation aus BDS; '' ohne.</summary>
function RtlRoot: string;
begin
  Result := GetEnvironmentVariable('BDS');
  if Result <> '' then
  begin
    Result := TPath.Combine(TPath.Combine(Result, 'source'), 'rtl');
  end;
  if (Result <> '') and not TDirectory.Exists(Result) then
  begin
    Result := '';
  end;
end;

/// <summary>Unit AFile aus dem Ordner AFolder der RTL ARoot wie unter Win64 mit Delphi 13 in den Index.</summary>
procedure AddRtlUnit(const AIndex: ISymbolIndex; const ARoot, AFolder, AFile: string);
var
  mFileName, mText: string;
begin
  mFileName := TPath.Combine(TPath.Combine(ARoot, AFolder), AFile);
  Assert.IsTrue(TIncludeFiles.ReadFile(mFileName, mText), mFileName);
  AIndex.AddUnit(TIndexExtractor.ExtractText(mText, mFileName, TArray<string>.Create('MSWINDOWS', 'WIN64', 'CPUX64',
    'CPU64BITS', 'UNICODE', 'NATIVECODE', 'CONDITIONALEXPRESSIONS', 'VER370', 'ASSEMBLER'),
    TIncludeFiles.Resolver(TArray<string>.Create(TPath.Combine(ARoot, 'sys'), TPath.Combine(ARoot, 'common')))));
end;

procedure TInliningRulesTests.RealRtlNeedsNoImplicitOrGenericUnit;
const
  cHalter =
    'unit Werk.Halter;'#10 +
    'interface'#10 +
    'uses System.Generics.Collections;'#10 +
    'type'#10 +
    '  THalter = class'#10 +
    '  public'#10 +
    '    Liste: TObjectList<TObject>;'#10 +
    '    Zahlen: TList<Integer>;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Werk.Halter;'#10 +
    'procedure Lauf(H: THalter);'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    '  C: Char;'#10 +
    'begin'#10 +
    '  TMonitor.Enter(H);'#10 +
    '  System.TMonitor.Enter(H);'#10 +
    '  System.TMonitor.Exit(H);'#10 +
    '  X := Pos(''='', ''a=b'') + H.Zahlen[0];'#10 +
    '  C := UpCase(''a'');'#10 +
    '  if H.Liste[X] = nil then'#10 +
    '    X := Ord(C);'#10 +
    'end;'#10 +
    'end.';
var
  mRoot: string;
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mWithRefs: string;
begin
  mRoot := RtlRoot;
  // Ohne Assert.Pass wie ParsesDelphiSourceCorpus (Leckmonitor).
  if mRoot = '' then
  begin
    System.Writeln('  Übersprungen: keine Delphi-RTL (BDS setzen)');
    Exit;
  end;
  mIndex := TSymbolIndex.Create;
  AddRtlUnit(mIndex, mRoot, 'sys', 'System.pas');
  AddRtlUnit(mIndex, mRoot, 'sys', 'SysInit.pas');
  AddRtlUnit(mIndex, mRoot, 'common', 'System.Generics.Defaults.pas');
  AddRtlUnit(mIndex, mRoot, 'common', 'System.Generics.Collections.pas');
  mIndex.AddUnit(TIndexExtractor.ExtractText(cHalter, 'C:\P\Werk.Halter.pas', nil));
  // Die Rümpfe haben Verweise: Ohne die Ausnahmen verlangte die Regel System bzw. System.Generics.Collections.
  Assert.IsTrue(mIndex.FindUnit('System', mUnit));
  mWithRefs := '';
  for mSymbol in mUnit.Symbols do
  begin
    if ((mSymbol.Name = 'Pos') or (mSymbol.QualifiedName = 'TMonitor.Enter')) and (mSymbol.InlineRefs <> nil) and
      not TInlineCallees.IsWithoutRefs(mSymbol) and not ContainsText(mWithRefs, mSymbol.QualifiedName + '|') then
    begin
      mWithRefs := mWithRefs + mSymbol.QualifiedName + '|';
    end;
  end;
  Assert.IsTrue(ContainsText(mWithRefs, 'TMonitor.Enter|'), mWithRefs);
  Assert.IsTrue(ContainsText(mWithRefs, 'Pos|'), mWithRefs);
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, mIndex, '',
    'Haupt.pas')));
  mWithRefs := '';
end;

procedure TInliningRulesTests.QuickFixAddsUnit;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Haupt('Werk.Json', '  X := F.Anzahl;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('uses Werk.Listen ergänzen', mFound[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes[0].Edits)));
  Assert.AreEqual(#10#10'uses'#10'  Werk.Listen;', mFound[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(3, mFound[0].Fixes[0].Edits[0].Range.StartPos.Line);
end;

procedure TInliningRulesTests.StrictPrivateMember;
begin
  // Delphi 13 bettet auch mit Zugriff auf strict private aus einer anderen Unit ohne H2444 ein (#1383,
  // Cm.H2440b, Cm.H2444).
  Assert.AreEqual('', Messages(Findings(Haupt('Werk.Json', '  X := F.Geheim;'#10))));
end;

procedure TInliningRulesTests.StrictPrivateInSameUnit;
const
  cSource =
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
begin
  // In derselben Unit ebenso still (#1383), mit und ohne Projektindex.
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, nil, '',
    'Haupt.pas')));
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource,
    TSymbolIndex.Create, '', 'Haupt.pas')));
end;

procedure TInliningRulesTests.InlineCallerWithImplementationUses;
const
  cSource =
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
    Messages(Findings(cSource)));
end;

procedure TInliningRulesTests.InlineCallerWithoutBodyReferences;
const
  cSource =
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
    Messages(Findings(cSource)));
  Assert.AreEqual('', Messages(Findings(ReplaceStr(ReplaceStr(cSource, 'uses Werk.Mathe;'#10, ''),
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
  cSource =
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
    'Unit Haupt indirekt über Werk.Kreis (wie H2457).|', Messages(Findings(cSource)));
end;

procedure TInliningRulesTests.SwitchableAndInlineOff;
var
  mSource: string;
begin
  mSource := Haupt('Werk.Json', '  X := F.Anzahl;'#10);
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"inline-not-expanded": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource,
    '{"rules": {"inline-not-expanded": {"severity": "hint", "exclude": ["Haupt.pas"]}}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(ReplaceStr(mSource, 'implementation'#10,
    'implementation'#10'{$INLINE OFF}'#10)))));
  // Ohne Index kennt die Regel Werk.Json nicht und schweigt.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, mSource, nil, '',
    'Haupt.pas'))));
end;

procedure TInliningRulesTests.IndexKeepsBodyReferences;
var
  mUnitIndex: TUnitIndex;
  mSymbol: TIndexSymbol;
  mRefs: string;
begin
  mUnitIndex := TIndexExtractor.ExtractText(cUnitJson, 'C:\P\Werk.Json.pas', nil);
  mRefs := '';
  for mSymbol in mUnitIndex.Symbols do
  begin
    if mSymbol.InInterface and (mSymbol.InlineRefs <> nil) then
    begin
      mRefs := mRefs + mSymbol.QualifiedName + '=' + String.Join(',', mSymbol.InlineRefs) + '|';
    end;
  end;
  // Lokale Namen, Result, eigene Typen und Mitglieder ohne weiteren Zugriff fehlen; Normal und Nochmal sind
  // nicht inline. Eingebaute Typen (Integer) löst erst die Regel auf.
  // Typverweise nennen das benutzte Mitglied (#2309).
  Assert.AreEqual('TJsonFeld.GetZahl=:TListe<Integer>#Count|TJsonFeld.Anzahl=:Integer,:TListe<Integer>#Count|' +
    'TJsonFeld.Geheim=!FGeheim|TJsonFeld.GetEnumerator=:TListe<Integer>#Count|' +
    'TJsonFeld.GetWert=:TListe<Integer>#Count|TJsonFeld.GetStil=:TListe<Integer>#Count,Include,Fett|Doppelt=Mal2|',
    mRefs);
  // Ohne Verweise bleibt die inline-Routine erkennbar (#1381); Mal2 ist nicht inline.
  mUnitIndex := TIndexExtractor.ExtractText(cUnitMathe, 'C:\P\Werk.Mathe.pas', nil);
  mRefs := '';
  for mSymbol in mUnitIndex.Symbols do
  begin
    if mSymbol.InInterface and (mSymbol.InlineRefs <> nil) then
    begin
      mRefs := mRefs + mSymbol.QualifiedName + '=' + IntToStr(Length(mSymbol.InlineRefs)) + ':' +
        String.Join(',', mSymbol.InlineRefs) + '|';
    end;
  end;
  Assert.AreEqual('Halb=1:|', mRefs);
end;

procedure TInliningRulesTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cInlineNotExpandedRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

procedure TInliningRulesTests.UnknownCallKeepsSuppression;
var
  mFound: TArray<TRuleFinding>;
begin
  // RenameFile kennt der Index nicht (RTL fehlt): Die Regel kann die Zeile nicht entscheiden, ihr lsp-ignore ist
  // keine unused-suppression. In einer Zeile mit nur bekannten Namen schon.
  mFound := Findings(Haupt('Werk.Json', '  RenameFile(''a'', ''b''); // lsp-ignore: inline-not-expanded'#10));
  Assert.AreEqual(0, Integer(Length(mFound)), Messages(mFound));
  mFound := Findings(Haupt('Werk.Json', '  X := 1; // lsp-ignore: inline-not-expanded'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('unused-suppression', mFound[0].RuleId);
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
  // cRoutines Routinen mit je cCallsPerRoutine Aufrufen. Werk.Basis.Wert ist inline und braucht Werk.Typen; Werk.Basis
  // verwendet Kette1, die Kette läuft über
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
    begin
      mNext := Format('uses Kette%d, Werk.Typen;'#10, [mStep + 1]);
    end
    else
    begin
      mNext := 'uses Werk.Typen;'#10;
    end;
    mIndex.AddUnit(TIndexExtractor.ExtractText(Format('unit Kette%d;'#10'interface'#10'%s' +
      'implementation'#10'end.', [mStep, mNext]), Format('C:\P\Kette%d.pas', [mStep]), nil));
  end;
  mBuilder := TStringBuilder.Create;
  try
    for mStep := 1 to cRoutines do
    begin
      mBuilder.Append(Format('procedure Lauf%d;'#10'var'#10'  X: Integer;'#10'begin'#10'  X := 0;'#10, [mStep]));
      for mCall := 1 to cCallsPerRoutine do
      begin
        mBuilder.Append('  X := Wert(X);'#10);
      end;
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
