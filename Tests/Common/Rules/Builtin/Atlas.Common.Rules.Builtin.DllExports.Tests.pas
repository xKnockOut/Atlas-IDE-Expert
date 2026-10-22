unit Atlas.Common.Rules.Builtin.DllExports.Tests;

// Tests für dll-export-unsafe (#973): Beispiel aus dem Issue mit Korrektur,
// alle unsicheren Typen, Überladungen, ShareMem und allowShareMem,
// Deklaration im interface einer Unit, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExportRulesTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure CorrectedFormIsSilent;
    [Test]
    procedure UnsafeTypes;
    [Test]
    procedure ShareMemAndOption;
    [Test]
    procedure OverloadsAndOtherUnits;
    [Test]
    procedure UnitWithInterfaceDeclaration;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Builtin.DllExports,
  Atlas.Tests.RuleAssert;

function Library_(const AUses, ADecls, AExports: string): string;
begin
  Result := 'library Kunden;'#10 + AUses + ADecls + 'exports'#10'  ' + AExports + ';'#10'begin'#10'end.';
end;

function Found(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDllExportUnsafeRule.Create, ASource);
end;

function Found(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDllExportUnsafeRule.Create, ASource, AConfig, 'Kunden.dpr');
end;

const
  // Beispiel aus #973
  KundeName = 'function KundeName(Id: Integer): string;'#10'begin'#10'  Result := '''';'#10'end;'#10;

procedure TExportRulesTests.IssueExampleWithFix;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Library_('', KundeName, 'KundeName');
  Findings := Found(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Exportierte Funktion gibt string zurück und hat keine Aufrufkonvention; Aufrufer ohne ShareMem ' +
    'stürzen ab. Besser PChar mit Puffer und Länge übergeben.', Findings[0].Message);
  // Am Eintrag in exports
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Aufrufkonvention stdcall ergänzen', Findings[0].Fixes[0].Title);
  Assert.IsFalse(Findings[0].Fixes[0].Safe);
  Assert.AreEqual(StringReplace(Source, 'string;'#10, 'string; stdcall;'#10, []),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // Mit Konvention bleibt der string gemeldet, ohne Korrektur.
  Findings := Found(TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Exportierte Funktion gibt string zurück; Aufrufer ohne ShareMem stürzen ab. Besser PChar mit ' +
    'Puffer und Länge übergeben.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TExportRulesTests.CorrectedFormIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Found(Library_('',
    'function KundeName(Id: Integer; Puffer: PChar; Laenge: Integer): Integer; stdcall;'#10'begin'#10 +
    '  Result := 0;'#10'end;'#10'procedure Zeige(const Text: WideString; Wert: Double); cdecl;'#10'begin'#10'end;'#10,
    'KundeName, Zeige')))));
  // Nicht aufgelöst: Routine aus einer anderen Unit, unbekannter Typ
  Assert.AreEqual(0, Integer(Length(Found(Library_('uses'#10'  Fremd;'#10,
    'procedure Lies(Wert: TUnbekannt); stdcall;'#10'begin'#10'end;'#10, 'Fremd.Schreibe, Lies')))));
end;

procedure TExportRulesTests.UnsafeTypes;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Found(Library_('', 'type'#10'  ILog = interface'#10'    procedure Schreibe;'#10'  end;'#10 +
    '  IGut = interface'#10'    [''{5CCE4184-2A0F-49C4-9B27-84C08CAC8109}'']'#10'  end;'#10 +
    '  TZahlen = array of Integer;'#10'  TFest = array[0..3] of Integer;'#10'  TKunde = class'#10'  end;'#10 +
    'procedure Setze(B: TBytes; Z: TZahlen; F: TFest; L: ILog; G: IGut; K: TKunde; S: TStringList); stdcall;'#10 +
    'begin'#10'end;'#10, 'Setze'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Exportierte Prozedur hat den Parameter B: TBytes (dynamisches Array), hat den Parameter Z: ' +
    'TZahlen (dynamisches Array), hat den Parameter L: ILog (Interface ohne GUID), hat den Parameter K: TKunde ' +
    '(Objekt) und hat den Parameter S: TStringList (Objekt); Aufrufer ohne ShareMem stürzen ab. Besser PChar mit ' +
    'Puffer und Länge übergeben.', Findings[0].Message);
  // Nur Objekte und Interfaces: andere Begründung
  Findings := Found(Library_('', 'function Liste: TStringList; stdcall;'#10'begin'#10'  Result := nil;'#10'end;'#10,
    'Liste'));
  Assert.AreEqual('Exportierte Funktion gibt TStringList (Objekt) zurück; Aufrufer aus anderen Sprachen oder ' +
    'Delphi-Versionen stürzen ab.', Findings[0].Message);
end;

procedure TExportRulesTests.ShareMemAndOption;
var
  Source: string;
begin
  Source := Library_('uses'#10'  ShareMem, System.SysUtils;'#10, StringReplace(KundeName, 'string;', 'string; stdcall;',
    []), 'KundeName');
  // Mit ShareMem sind Strings erlaubt.
  Assert.AreEqual(0, Integer(Length(Found(Source))));
  Assert.AreEqual(1, Integer(Length(Found(Source, '{"rules": {"dll-export-unsafe": {"allowShareMem": false}}}'))));
  // Ohne Aufrufkonvention bleibt die Meldung.
  Assert.AreEqual('Exportierte Funktion hat keine Aufrufkonvention; Aufrufer aus anderen Sprachen oder ' +
    'Delphi-Versionen stürzen ab.', Found(StringReplace(Source, ' stdcall;', '', []))[0].Message);
end;

procedure TExportRulesTests.OverloadsAndOtherUnits;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Library_('', 'procedure Setze(const A: string); overload; stdcall;'#10'begin'#10'end;'#10 +
    'procedure Setze(A: Integer); overload;'#10'begin'#10'end;'#10,
    'Setze(const A: string) name ''SetzeText'','#10'  Setze(A: Integer) name ''SetzeZahl''');
  Findings := Found(Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Exportierte Prozedur hat den Parameter A: string; Aufrufer ohne ShareMem stürzen ab. Besser ' +
    'PChar mit Puffer und Länge übergeben.', Findings[0].Message);
  Assert.AreEqual('Exportierte Prozedur hat keine Aufrufkonvention; Aufrufer aus anderen Sprachen oder ' +
    'Delphi-Versionen stürzen ab.', Findings[1].Message);
  Assert.AreEqual(StringReplace(Source, 'Integer); overload;', 'Integer); overload; stdcall;', []),
    TChangeSignature.ApplyEdits(Source, Findings[1].Fixes[0].Edits));
end;

procedure TExportRulesTests.UnitWithInterfaceDeclaration;
const
  Source = 'unit Dienst;'#10'interface'#10'function Version: Integer;'#10'implementation'#10 +
    'function Version: Integer;'#10'begin'#10'  Result := 1;'#10'end;'#10'exports'#10'  Version;'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Found(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  // Beide Köpfe bekommen die Konvention.
  Assert.AreEqual(StringReplace(Source, 'Integer;', 'Integer; stdcall;', [rfReplaceAll]),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // Konvention nur im interface genügt.
  Assert.AreEqual(0, Integer(Length(Found(StringReplace(Source, 'interface'#10'function Version: Integer;',
    'interface'#10'function Version: Integer; stdcall;', [])))));
end;

procedure TExportRulesTests.OffAndExclude;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Library_('', KundeName, 'KundeName');
  Assert.AreEqual(0, Integer(Length(Found(Source, '{"rules": {"dll-export-unsafe": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Found(Source, '{"rules": {"group:robustness": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDllExportUnsafeRule.Create, Source,
    '{"rules": {"dll-export-unsafe": {"exclude": ["Alt/*.dpr"]}}}', 'Alt/Kunden.dpr'))));
  TConfigurationParser.Parse('{"rules": {"dll-export-unsafe": {"allowShareMem": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowShareMem" muss true oder false sein', Issues[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TExportRulesTests);

end.
