unit Atlas.Common.Rules.Builtin.Published.Tests;

// Tests der Regel published-type-invalid (#1004): Property-Typen, die das
// Streaming nicht kennt, Real48, große Mengen, Felder, Überladungen,
// Klassen-Properties, Nicht-ASCII-Namen, bedingte Zweige, Typen aus dem
// Index, Korrektur und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPublishedRulesTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure CorrectedAndNegativeCases;
    [Test]
    procedure ArraysPointersAndProcedures;
    [Test]
    procedure Real48AndLargeSets;
    [Test]
    procedure PublishedFields;
    [Test]
    procedure OverloadsClassPropertiesAndNames;
    [Test]
    procedure FixUsesExistingPublic;
    [Test]
    procedure ConditionalAndGenericAreSilent;
    [Test]
    procedure TypesFromIndex;
    [Test]
    procedure Options;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Published,
  Atlas.Tests.RuleAssert;

const
  /// <summary>Typen für die Tests; Zeilen 4 bis 13 der Unit.</summary>
  Typen = '  TZahlen = array of Integer;'#10'  TFeld = array[0..3] of Byte;'#10'  PKnoten = ^Integer;'#10 +
    '  TRueckruf = procedure(A: Integer);'#10'  TEreignis = procedure(Sender: TObject) of object;'#10 +
    '  TFarbe = (Rot, Gruen, Blau);'#10'  TFarben = set of TFarbe;'#10'  TPunkt = record X, Y: Integer; end;'#10 +
    '  TKnopf = class end;'#10'  IAnzeige = interface end;'#10;

/// <summary>Unit mit TKarte = class(TComponent): private-Teil APrivate, published-Teil APublished.</summary>
function Karte(const APrivate, APublished: string): string;
begin
  Result := 'unit Karten;'#10'interface'#10'uses'#10'  System.Types, Classes;'#10'type'#10 + Typen +
    '  TKarte = class(TComponent)'#10'  private'#10 + APrivate + '  published'#10 + APublished + '  end;'#10 +
    'implementation'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TPublishedTypeInvalidRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TPublishedTypeInvalidRule.Create, ASource, AConfig, APath);
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

function Join(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
    Result := Result + ' | ' + Finding.Message;
end;

procedure Silent(const ASource: string);
begin
  TRuleAssert.Silent(TPublishedTypeInvalidRule.Create, ASource);
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

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an, auch über Zeilen.</summary>
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

{ TPublishedRulesTests }

procedure TPublishedRulesTests.IssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Karte('    FMitte: TPointF;'#10'    procedure SetMitte(const Value: TPointF);'#10,
    '    property Mitte: TPointF read FMitte write SetMitte;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TPointF (Record) kann nicht published sein (wie E2188).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
  Assert.AreEqual(20, Found[0].Range.StartPos.Line);
  Assert.AreEqual(20, Found[0].Range.StartPos.Character);
  Assert.AreEqual(27, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In den public-Abschnitt verschieben', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Karte('    FMitte: TPointF;'#10'    procedure SetMitte(const Value: TPointF);'#10'  public'#10 +
    '    property Mitte: TPointF read FMitte write SetMitte;'#10, ''), Fixed);
  Silent(Fixed);
end;

procedure TPublishedRulesTests.CorrectedAndNegativeCases;
begin
  // Erlaubte Typen: Ordinal, String, Gleitkomma, Aufzählung, kleine Menge, Methodenzeiger, Klasse, Interface.
  Silent(Karte('', '    property Zahl: Integer read FZahl;'#10'    property Text: string read FText;'#10 +
    '    property Wert: Double read FWert;'#10'    property Farbe: TFarbe read FFarbe;'#10 +
    '    property Farben: TFarben read FFarben;'#10'    property OnKlick: TEreignis read FOnKlick;'#10 +
    '    property Knopf: TKnopf read FKnopf;'#10'    property Anzeige: IAnzeige read FAnzeige;'#10 +
    '    property Datum: TDateTime read FDatum;'#10'    property Name;'#10 +
    '    property Fremd: TFremderTyp read FFremd;'#10'    procedure Klick(Sender: TObject);'#10 +
    '    FKomponente: TKnopf;'#10'    FAnzeige: IAnzeige;'#10));
  // public und der Abschnitt ohne Angabe: dort stuft der Compiler still herab.
  Silent('unit Karten;'#10'interface'#10'uses'#10'  System.Types;'#10'type'#10'  TKarte = class(TPersistent)'#10 +
    '    property Mitte: TPointF read FMitte;'#10'  public'#10'    property Ecke: TPointF read FEcke;'#10 +
    '  end;'#10'implementation'#10'end.');
  // Ohne System.Types ist TPointF kein bekannter Typ.
  Silent('unit Karten;'#10'interface'#10'type'#10'  TKarte = class'#10'  published'#10 +
    '    property Mitte: TPointF read FMitte;'#10'  end;'#10'implementation'#10'end.');
end;

procedure TPublishedRulesTests.ArraysPointersAndProcedures;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Karte('', '    property Zahlen: TZahlen read FZahlen;'#10 +
    '    property Feld: TFeld read FFeld;'#10'    property Knoten: PKnoten read FKnoten;'#10 +
    '    property Puffer: PChar read FPuffer;'#10'    property Rueckruf: TRueckruf read FRueckruf;'#10 +
    '    property Liste: TArray<Integer> read FListe;'#10'    property Punkt: TPunkt read FPunkt;'#10 +
    '    property Kennung: TGUID read FKennung;'#10));
  Assert.AreEqual(8, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('TZahlen (Array) kann nicht published sein (wie E2188).', Found[0].Message);
  Assert.AreEqual('TFeld (Array) kann nicht published sein (wie E2188).', Found[1].Message);
  Assert.AreEqual('PKnoten (Zeiger) kann nicht published sein (wie E2188).', Found[2].Message);
  Assert.AreEqual('PChar (Zeiger) kann nicht published sein (wie E2188).', Found[3].Message);
  Assert.AreEqual('TRueckruf (Prozedurtyp ohne "of object") kann nicht published sein (wie E2188).',
    Found[4].Message);
  Assert.AreEqual('TArray<Integer> (Array) kann nicht published sein (wie E2188).', Found[5].Message);
  Assert.AreEqual('TPunkt (Record) kann nicht published sein (wie E2188).', Found[6].Message);
  Assert.AreEqual('TGUID (Record) kann nicht published sein (wie E2188).', Found[7].Message);
end;

procedure TPublishedRulesTests.Real48AndLargeSets;
var
  Source: string;
begin
  Assert.AreEqual('Alt ist vom Typ Real48; Real48 kann nicht published sein (wie E2186).',
    OnlyMessage(Karte('', '    property Alt: Real48 read FAlt;'#10)));
  Source := 'unit Mengen;'#10'interface'#10'type'#10'  TZeichen = (z0, z1, z2, z3, z4, z5, z6, z7, z8, z9, z10, ' +
    'z11, z12, z13, z14, z15, z16, z17, z18, z19, z20, z21, z22, z23, z24, z25, z26, z27, z28, z29, z30, z31, ' +
    'z32);'#10'  TGross = set of TZeichen;'#10'  TBytes_ = set of Byte;'#10'  TKlein = set of 0..31;'#10 +
    '  TBreit = set of 0..32;'#10'  TVerschoben = set of 8..39;'#10'  TMenge = class'#10'  published'#10 +
    '    property Gross: TGross read FGross;'#10'    property Bytes: TBytes_ read FBytes;'#10 +
    '    property Klein: TKlein read FKlein;'#10'    property Breit: TBreit read FBreit;'#10 +
    '    property Verschoben: TVerschoben read FVerschoben;'#10'  end;'#10'implementation'#10'end.';
  Assert.AreEqual(3, Integer(Length(Findings(Source))));
  Assert.AreEqual('Die Menge TGross ist größer als 4 Byte und kann nicht published sein (wie E2187).',
    Findings(Source)[0].Message);
  Assert.AreEqual('Die Menge TBytes_ ist größer als 4 Byte und kann nicht published sein (wie E2187).',
    Findings(Source)[1].Message);
  Assert.AreEqual('Die Menge TBreit ist größer als 4 Byte und kann nicht published sein (wie E2187).',
    Findings(Source)[2].Message);
end;

procedure TPublishedRulesTests.PublishedFields;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Karte('', '    FZahl, FAnzahl: Integer;'#10'    FPunkt: TPunkt;'#10'    FKnopf: TKnopf;'#10 +
    '    FFremd: TFremderTyp;'#10'    FGruppe: array[0..1] of TKnopf;'#10);
  Found := Findings(Source);
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Das published-Feld FZahl, FAnzahl ist vom Typ Integer; published-Felder müssen Klassen oder ' +
    'Interfaces sein (wie E2217).', Found[0].Message);
  Assert.AreEqual(18, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Das published-Feld FPunkt ist vom Typ TPunkt; published-Felder müssen Klassen oder ' +
    'Interfaces sein (wie E2217).', Found[1].Message);
  Assert.AreEqual('Das published-Feld FGruppe ist vom Typ array[0..1] of TKnopf; published-Felder müssen ' +
    'Klassen oder Interfaces sein (wie E2217).', Found[2].Message);
  Fixed := ApplyFix(Source, Found[1].Fixes[0]);
  Assert.AreEqual(Karte('  public'#10'    FPunkt: TPunkt;'#10, '    FZahl, FAnzahl: Integer;'#10 +
    '    FKnopf: TKnopf;'#10'    FFremd: TFremderTyp;'#10'    FGruppe: array[0..1] of TKnopf;'#10), Fixed);
end;

procedure TPublishedRulesTests.OverloadsClassPropertiesAndNames;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Karte('', '    procedure Laden; overload;'#10'    procedure Laden(const APfad: string); ' +
    'overload;'#10'    procedure Speichern;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Nur eine Überladung von Laden darf published sein (wie E2266).', Found[0].Message);
  Assert.AreEqual(19, Found[0].Range.StartPos.Line);
  // Eine Überladung in public zählt nicht, ebenso eine im anderen Zweig.
  Silent(Karte('', '    procedure Laden; overload;'#10'  public'#10'    procedure Laden(const APfad: string); ' +
    'overload;'#10));
  Silent(Karte('', '  {$IFDEF NEU}'#10'    procedure Laden(const APfad: string);'#10'  {$ELSE}'#10 +
    '    procedure Laden;'#10'  {$ENDIF}'#10));
  Assert.AreEqual('Die Klassen-Property Standard kann nicht published sein (wie E2545).',
    OnlyMessage(Karte('', '    class property Standard: Integer read FStandard;'#10)));
  Assert.AreEqual('Der published-Name Größe enthält Zeichen außerhalb von ASCII (wie E2452).',
    OnlyMessage(Karte('', '    property Größe: Integer read FGroesse;'#10)));
end;

procedure TPublishedRulesTests.FixUsesExistingPublic;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Karten;'#10'interface'#10'type'#10'  TPunkt = record X: Integer; end;'#10 +
    '  TKarte = class'#10'  public'#10'    constructor Create;'#10'  published'#10 +
    '    property Name: string read FName;'#10'    property Punkt: TPunkt read FPunkt;'#10'  end;'#10 +
    'implementation'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('unit Karten;'#10'interface'#10'type'#10'  TPunkt = record X: Integer; end;'#10 +
    '  TKarte = class'#10'  public'#10'    constructor Create;'#10'    property Punkt: TPunkt read FPunkt;'#10 +
    '  published'#10'    property Name: string read FName;'#10'  end;'#10'implementation'#10'end.',
    ApplyFix(Source, Found[0].Fixes[0]));
  // Ein Mitglied, das sich die Zeile mit anderem teilt, verschiebt die Korrektur nicht.
  Found := Findings(Karte('', '    property Punkt: TPunkt read FPunkt; property Name: string read FName;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TPublishedRulesTests.ConditionalAndGenericAreSilent;
begin
  // published nur in einem Zweig, das Mitglied in beiden.
  Silent(Karte('', '  public'#10'  {$IFDEF ALT}'#10'  published'#10'  {$ENDIF}'#10 +
    '    property Punkt: TPunkt read FPunkt;'#10));
  // Typparameter der Klasse passen zu allem; der Typ im inaktiven Zweig ist doppelt deklariert.
  Silent('unit Karten;'#10'interface'#10'type'#10'  TBox<T> = class'#10'  published'#10 +
    '    property Wert: T read FWert;'#10'    FInhalt: T;'#10'  end;'#10'implementation'#10'end.');
  Silent('unit Karten;'#10'interface'#10'type'#10'  {$IFDEF ALT}'#10'  TWert = record end;'#10'  {$ELSE}'#10 +
    '  TWert = class end;'#10'  {$ENDIF}'#10'  TKarte = class'#10'  published'#10 +
    '    property Wert: TWert read FWert;'#10'  end;'#10'implementation'#10'end.');
  // Records erlauben kein published; die Regel schaut nur auf Klassen.
  Silent('unit Karten;'#10'interface'#10'type'#10'  TPunkt = record X: Integer; end;'#10 +
    '  TObj = object'#10'  published'#10'    P: TPunkt;'#10'  end;'#10'implementation'#10'end.');
end;

procedure TPublishedRulesTests.TypesFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Geometrie;'#10'interface'#10'type'#10 +
    '  TVektor = record X, Y: Double; end;'#10'  TPunkte = TArray<TVektor>;'#10'  TFigur = class end;'#10 +
    '  TFlaeche = TVektor;'#10'implementation'#10'end.', 'C:\Projekt\Geometrie.pas', nil));
  Found := TRuleAssert.IndexFindings(TPublishedTypeInvalidRule.Create, 'unit Karten;'#10'interface'#10'uses'#10 +
    '  Geometrie;'#10'type'#10'  TKarte = class'#10'  published'#10'    property Mitte: TVektor read FMitte;'#10 +
    '    property Ecken: TPunkte read FEcken;'#10'    property Figur: TFigur read FFigur;'#10 +
    '    property Flaeche: TFlaeche read FFlaeche;'#10'    FFigur: TFigur;'#10'  end;'#10'implementation'#10 +
    'end.', Index, '', '');
  Assert.AreEqual(3, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('TVektor (Record) kann nicht published sein (wie E2188).', Found[0].Message);
  Assert.AreEqual('TPunkte (Array) kann nicht published sein (wie E2188).', Found[1].Message);
  Assert.AreEqual('TFlaeche (Record) kann nicht published sein (wie E2188).', Found[2].Message);
end;

procedure TPublishedRulesTests.Options;
var
  Source: string;
begin
  Source := Karte('', '    property Punkt: TPunkt read FPunkt;'#10);
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Karten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"published-type-invalid": "off"}}',
    'Source/Karten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Karten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"published-type-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Karten.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"published-type-invalid": {"exclude": ["Alt/*.pas"]}}}', 'Source/Karten.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPublishedRulesTests);

end.
