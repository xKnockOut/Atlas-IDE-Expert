unit Atlas.Common.Rules.Builtin.Visibility.Tests;

// Tests der Regeln zur Sichtbarkeit von Klassenmitgliedern:
// inaccessible-member (#1008): Beispiel aus dem Issue (E2124), private und
// protected aus einer anderen Unit (E2361, E2362), strict private in derselben
// Unit, stille Fälle (Nachfahren, protected über eine Klasse der eigenen Unit,
// with, class var), W1045 und die Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInaccessibleMemberTests = class
  public
    [Test]
    procedure IssueExampleInstanceFieldInClassMethod;
    [Test]
    procedure ClassMethodSilentCases;
    [Test]
    procedure PrivateAndProtectedOfOtherUnit;
    [Test]
    procedure DescendantsAndLocalClassesSeeProtected;
    [Test]
    procedure StrictPrivateInSameUnit;
    [Test]
    procedure PropertyReferencesAncestorPrivate;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Visibility,
  Atlas.Tests.RuleAssert;

/// <summary>System mit TObject und Unit Basis mit TBasis (private, strict private, protected, public).</summary>
function BasisIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  public'#10'    procedure Free;'#10'  end;'#10'implementation'#10'procedure TObject.Free;'#10'begin'#10'end;'#10 +
    'end.', 'C:\BDS\source\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TBasis = class'#10 +
    '  private'#10'    FGeheim: Integer;'#10'  strict private'#10'    FStreng: Integer;'#10'  protected'#10 +
    '    procedure Schuetzen;'#10'  strict protected'#10'    procedure StrengSchuetzen;'#10'  public'#10 +
    '    procedure Oeffnen;'#10'  end;'#10'implementation'#10'procedure TBasis.Schuetzen;'#10'begin'#10'end;'#10 +
    'procedure TBasis.StrengSchuetzen;'#10'begin'#10'end;'#10'procedure TBasis.Oeffnen;'#10'begin'#10'end;'#10 +
    'end.', 'C:\Projekt\Basis.pas', nil));
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TInaccessibleMemberRule.Create, ASource, BasisIndex, '', 'Kunden.pas');
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TInaccessibleMemberRule.Create, ASource, BasisIndex, AConfig, APath);
end;

/// <summary>Unit Kunden mit TKonfig (FBasisPfad, Pfad, class var Zaehler) und der Klassenmethode Standard.</summary>
function Konfig(const ABody: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'type'#10'  TKonfig = class'#10'  private'#10 +
    '    FBasisPfad: string;'#10'    class var FZaehler: Integer;'#10'    function GetName: string;'#10'  public'#10 +
    '    Pfad: string;'#10'    property Name: string read GetName;'#10'    class function Standard: TKonfig;'#10 +
    '    class function Leer: TKonfig; static;'#10'  end;'#10'implementation'#10 +
    'function TKonfig.GetName: string;'#10'begin'#10'  Result := FBasisPfad;'#10'end;'#10 +
    'class function TKonfig.Standard: TKonfig;'#10'begin'#10 + ABody + 'end;'#10 +
    'class function TKonfig.Leer: TKonfig;'#10'begin'#10'  Result := nil;'#10'  Pfad := '''';'#10'end;'#10'end.';
end;

/// <summary>Unit Kunden, die Basis einbindet; AType im interface, ABody in der Routine Arbeiten(B: TBasis).
/// </summary>
function Fremd(const AType, ABody: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'uses'#10'  Basis;'#10'type'#10 + AType + 'implementation'#10 +
    'procedure Arbeiten(B: TBasis);'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TInaccessibleMemberTests.IssueExampleInstanceFieldInClassMethod;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Konfig('  Result := TKonfig.Create;'#10'  Result.Pfad := FBasisPfad;'#10));
  // Die statische Methode Leer greift ebenfalls auf ein Instanzfeld zu.
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('FBasisPfad ist ein Instanzfeld und in der Klassenmethode Standard nicht erreichbar (wie E2124).',
    Found[0].Message);
  Assert.AreEqual(22, Found[0].Range.StartPos.Line);
  Assert.AreEqual(17, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Pfad ist ein Instanzfeld und in der Klassenmethode Leer nicht erreichbar (wie E2124).',
    Found[1].Message);
  Found := Findings(Konfig('  Result := nil;'#10'  if Name = '''' then'#10'    Free;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Name ist eine Instanz-Property und in der Klassenmethode Standard nicht erreichbar (wie E2124).',
    Found[0].Message);
  Assert.AreEqual('Free ist eine Instanzmethode und in der Klassenmethode Standard nicht erreichbar (wie E2124).',
    Found[1].Message);
end;

procedure TInaccessibleMemberTests.ClassMethodSilentCases;
var
  Found: TArray<TRuleFinding>;
begin
  // Korrigierte Form, class var, Konstruktor, with und lokale Variable.
  Found := Findings(Konfig('  Result := TKonfig.Create;'#10'  Result.Pfad := Result.FBasisPfad;'#10 +
    '  Inc(FZaehler);'#10'  with Result do'#10'    Pfad := FBasisPfad;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), 'nur Leer');
  Assert.AreEqual(30, Found[0].Range.StartPos.Line);
  Found := Findings(Konfig('  Result := Create;'#10).Replace('begin'#10'  Result := Create',
    'var'#10'  Pfad: string;'#10'begin'#10'  Pfad := '''';'#10'  Result := Create'));
  Assert.AreEqual(1, Integer(Length(Found)), 'nur Leer');
end;

procedure TInaccessibleMemberTests.PrivateAndProtectedOfOtherUnit;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Fremd('', '  B.FGeheim := 1;'#10'  B.Schuetzen;'#10'  B.StrengSchuetzen;'#10 +
    '  B.Oeffnen;'#10'  Unbekannt.FGeheim := 2;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('TBasis.FGeheim ist private und hier nicht sichtbar (wie E2361).', Found[0].Message);
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  Assert.AreEqual(11, Found[0].Range.EndPos.Character);
  Assert.AreEqual('TBasis.Schuetzen ist protected und hier nicht sichtbar (wie E2362).', Found[1].Message);
  Assert.AreEqual('TBasis.StrengSchuetzen ist strict protected und hier nicht sichtbar (wie E2362).',
    Found[2].Message);
end;

procedure TInaccessibleMemberTests.DescendantsAndLocalClassesSeeProtected;
var
  Source: string;
begin
  // Methode eines Nachfahren und protected über eine Klasse der eigenen Unit (TZugang(B).Schuetzen).
  Source := 'unit Kunden;'#10'interface'#10'uses'#10'  Basis;'#10'type'#10'  TKunde = class(TBasis)'#10 +
    '    procedure Laden(B: TBasis);'#10'  end;'#10'  TZugang = class(TBasis)'#10'  end;'#10'implementation'#10 +
    'procedure TKunde.Laden(B: TBasis);'#10'begin'#10'  Schuetzen;'#10'  Self.StrengSchuetzen;'#10 +
    '  B.Schuetzen;'#10'end;'#10'procedure Arbeiten(B: TBasis);'#10'begin'#10'  TZugang(B).Schuetzen;'#10 +
    'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(Findings(Source))));
  // private bleibt auch für Nachfahren in einer anderen Unit unsichtbar.
  Assert.AreEqual(1, Integer(Length(Findings(Source.Replace('  B.Schuetzen;', '  B.FGeheim := 0;')))));
end;

procedure TInaccessibleMemberTests.StrictPrivateInSameUnit;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Kunden;'#10'interface'#10'type'#10'  TLager = class'#10'  private'#10'    FBestand: Integer;'#10 +
    '  strict private'#10'    FReserve: Integer;'#10'  end;'#10'  TKasse = class'#10'    procedure Buchen(L: TLager);'#10 +
    '  end;'#10'implementation'#10'procedure TKasse.Buchen(L: TLager);'#10'begin'#10'  L.FBestand := 1;'#10 +
    '  L.FReserve := 2;'#10'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TLager.FReserve ist strict private und hier nicht sichtbar (wie E2361).', Found[0].Message);
  Assert.AreEqual(16, Found[0].Range.StartPos.Line);
end;

procedure TInaccessibleMemberTests.PropertyReferencesAncestorPrivate;
var
  Found: TArray<TRuleFinding>;
  Source: string;
begin
  Source := 'unit Kunden;'#10'interface'#10'type'#10'  TBasis = class'#10'  private'#10'    FWert: Integer;'#10 +
    '  protected'#10'    FSchutz: Integer;'#10'  end;'#10'  TKind = class(TBasis)'#10'  public'#10 +
    '    property Wert: Integer read FWert write FWert;'#10'    property Schutz: Integer read FSchutz;'#10 +
    '  end;'#10'implementation'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Property Wert verweist auf TBasis.FWert, das im Vorfahren private ist (wie W1045).',
    Found[0].Message);
  Assert.AreEqual(Integer(Ord(TRuleSeverity.Warning)), Integer(Ord(Found[0].Severity)));
  Assert.AreEqual(11, Found[0].Range.StartPos.Line);
  // Eigenes Feld derselben Klasse: still.
  Assert.AreEqual(0, Integer(Length(Findings(Source.Replace('  TKind = class(TBasis)'#10'  public'#10,
    '  TKind = class(TBasis)'#10'  private'#10'    FWert: Integer;'#10'  public'#10)))));
end;

procedure TInaccessibleMemberTests.OffAndExclude;
var
  Source: string;
begin
  Source := Fremd('', '  B.FGeheim := 1;'#10);
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"inaccessible-member": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"inaccessible-member": {"exclude": ["Source/*.pas"]}}}',
    'Source/Kunden.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TInaccessibleMemberTests);

end.
