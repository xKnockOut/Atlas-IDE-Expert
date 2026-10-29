unit Atlas.Common.Rules.Builtin.DefaultProperty.Tests;

// Tests der Regel default-property-invalid (#1073) aus Rules.Builtin.Properties:
// default an einer Property ohne Index (E2132), zwei default-Properties mit
// denselben Indextypen (E2131), Obj[I] auf einer Klasse ohne default-Property
// (E2149), Typen aus dem Index und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDefaultPropertyRulesTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure SecondDefaultProperty;
    [Test]
    procedure IndexWithoutDefaultProperty;
    [Test]
    procedure SilentAccesses;
    [Test]
    procedure TypesFromIndex;
    /// <summary>Lokale Konstante als Array von Klassenreferenzen (#1326, Indy HashTypes[I]): Das erste Element
    /// der Liste ist nicht ihr Typ.</summary>
    [Test]
    procedure ConstArrayOfClassReferences;
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
  Atlas.Common.Rules.Builtin.Properties,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit der Klasse TListe (AMembers) und den Rümpfen ABodies.</summary>
function Listen(const AMembers, ABodies: string): string;
begin
  Result := 'unit Listen;'#10'interface'#10'type'#10'  TListe = class'#10 + AMembers + '  end;'#10 +
    'implementation'#10 + ABodies + 'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDefaultPropertyInvalidRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDefaultPropertyInvalidRule.Create, ASource, AConfig, APath);
end;

function Join(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
    Result := Result + ' | ' + Finding.Message;
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource + Join(Found));
  Result := Found[0].Message;
end;

procedure Silent(const ASource: string);
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(0, Integer(Length(Found)), ASource + Join(Found));
end;

{ TDefaultPropertyRulesTests }

procedure TDefaultPropertyRulesTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Listen('  private'#10'    FName: string;'#10'  public'#10 +
    '    property Name: string read FName; default;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('default ist nur an Array-Properties erlaubt (wie E2132).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(38, Found[0].Range.StartPos.Character);
  // Korrigiert: Array-Property mit default, Speicher-Standardwert "default 0" an einer einfachen Property.
  Silent(Listen('  private'#10'    FName: string;'#10'    FZahl: Integer;'#10 +
    '    function GetItem(I: Integer): string;'#10'  public'#10 +
    '    property Items[I: Integer]: string read GetItem; default;'#10 +
    '    property Zahl: Integer read FZahl default 0;'#10, ''));
end;

procedure TDefaultPropertyRulesTests.SecondDefaultProperty;
begin
  Assert.AreEqual('TListe hat schon die default-Property Items mit denselben Indextypen (wie E2131).',
    OnlyMessage(Listen('    function GetItem(I: Integer): string;'#10'    function GetText(I: Integer): string;'#10 +
    '    property Items[I: Integer]: string read GetItem; default;'#10 +
    '    property Texte[I: Integer]: string read GetText; default;'#10, '')));
  // Überladung über den Indextyp ist erlaubt; ebenso in einer anderen Klasse.
  Silent(Listen('    function GetItem(I: Integer): string;'#10'    function GetNamed(const N: string): string;'#10 +
    '    property Items[I: Integer]: string read GetItem; default;'#10 +
    '    property Named[const N: string]: string read GetNamed; default;'#10, ''));
  Silent('unit Listen;'#10'interface'#10'type'#10'  TA = class'#10'    function G(I: Integer): string;'#10 +
    '    property Items[I: Integer]: string read G; default;'#10'  end;'#10'  TB = class(TA)'#10 +
    '    function H(I: Integer): string;'#10'    property Texte[I: Integer]: string read H; default;'#10 +
    '  end;'#10'implementation'#10'end.');
end;

procedure TDefaultPropertyRulesTests.IndexWithoutDefaultProperty;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Listen('    FAnzahl: Integer;'#10, 'procedure Zeigen;'#10'var'#10'  L: TListe;'#10 +
    'begin'#10'  L := TListe.Create;'#10'  L[0] := nil;'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('TListe hat keine default-Property; L[…] braucht eine (wie E2149).', Found[0].Message);
  Assert.AreEqual(12, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
end;

procedure TDefaultPropertyRulesTests.SilentAccesses;
begin
  // Default-Property in der Klasse oder im Vorfahren, Array-Property, Strings, Arrays, unbekannte Typen.
  Silent('unit Listen;'#10'interface'#10'type'#10'  TBasis = class'#10'    function G(I: Integer): TObject;'#10 +
    '    property Items[I: Integer]: TObject read G; default;'#10'  end;'#10'  TListe = class(TBasis)'#10 +
    '    function H(I: Integer): TBasis;'#10'    property Kinder[I: Integer]: TBasis read H;'#10'  end;'#10 +
    'implementation'#10'procedure Zeigen;'#10'var'#10'  L: TListe;'#10'  S: string;'#10 +
    '  A: array of Integer;'#10'  F: TFremd;'#10'begin'#10'  L[0].Free;'#10'  L.Kinder[0].Free;'#10 +
    '  L.Kinder[0][1].Free;'#10'  S[1] := ''x'';'#10'  A[0] := 1;'#10'  F[0] := 1;'#10'end;'#10'end.');
  // Unbekannter Vorfahr: keine Aussage.
  Silent('unit Listen;'#10'interface'#10'type'#10'  TListe = class(TFremd)'#10'  end;'#10'implementation'#10 +
    'procedure Zeigen(L: TListe);'#10'begin'#10'  L[0] := nil;'#10'end;'#10'end.');
end;

procedure TDefaultPropertyRulesTests.TypesFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Behaelter;'#10'interface'#10'type'#10'  TSack = class'#10 +
    '    FAnzahl: Integer;'#10'  end;'#10'  TBeutel = class'#10'    function G(I: Integer): Integer;'#10 +
    '    property Items[I: Integer]: Integer read G; default;'#10'  end;'#10'implementation'#10'end.',
    'C:\Projekt\Behaelter.pas', nil));
  Found := TRuleAssert.IndexFindings(TDefaultPropertyInvalidRule.Create, 'unit Listen;'#10'interface'#10 +
    'uses'#10'  Behaelter;'#10'implementation'#10'procedure Zeigen(S: TSack; B: TBeutel);'#10'begin'#10 +
    '  S[0] := 1;'#10'  B[0] := 1;'#10'end;'#10'end.', Index, '', '');
  Assert.AreEqual(1, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('TSack hat keine default-Property; S[…] braucht eine (wie E2149).', Found[0].Message);
end;

procedure TDefaultPropertyRulesTests.Options;
var
  Source: string;
begin
  Source := Listen('    property Name: string read FName; default;'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Listen.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"default-property-invalid": "off"}}',
    'Source/Listen.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Listen.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"default-property-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Listen.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"default-property-invalid": {"exclude": ["Alt/*.pas"]}}}', 'Source/Listen.pas'))));
end;

procedure TDefaultPropertyRulesTests.ConstArrayOfClassReferences;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Findings('unit Pruefsummen;'#10'interface'#10'type'#10'  THash = class'#10'  public'#10 +
    '    constructor Create(AOwner: TObject); virtual;'#10'  end;'#10'  THashA = class(THash);'#10 +
    '  THashB = class(THash);'#10'  THashClass = class of THash;'#10'implementation'#10 +
    'constructor THash.Create(AOwner: TObject);'#10'begin'#10'end;'#10'procedure Pruefen(AIndex: Integer);'#10 +
    'const'#10'  cArten: array[0..1] of THashClass = (THashA, THashB);'#10'var'#10'  mHash: THash;'#10 +
    'begin'#10'  mHash := cArten[AIndex].Create(nil);'#10'  mHash.Free;'#10'  mHash := nil;'#10 +
    '  mHash[0].Free;'#10'end;'#10'end.');
  // Gemeldet bleibt nur der Index auf die Instanz ohne default-Property.
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('THash hat keine default-Property; mHash[…] braucht eine (wie E2149).', mFindings[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TDefaultPropertyRulesTests);

end.
