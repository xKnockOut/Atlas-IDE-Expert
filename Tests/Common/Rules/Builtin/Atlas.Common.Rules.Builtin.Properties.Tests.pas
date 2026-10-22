unit Atlas.Common.Rules.Builtin.Properties.Tests;

// Tests der Regel property-accessor-invalid (#1001): fehlende und falsche
// Getter, Setter und Felder hinter read/write, Klassen-Properties,
// Feldselektoren, Vorfahren aus dem Index, Korrektur und Einstellungen.
// write-only-property (#978): Beispiel, Korrektur read FName, Properties ohne
// Typ, allowAttributes samt Parserprüfung, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPropertyRulesTests = class
  public
    [Test]
    procedure AccessorIssueExample;
    [Test]
    procedure AccessorValidFormsAreSilent;
    [Test]
    procedure AccessorMissingFixes;
    [Test]
    procedure AccessorWrongKinds;
    [Test]
    procedure AccessorSignatures;
    [Test]
    procedure AccessorClassAndInstance;
    [Test]
    procedure AccessorFieldSelectors;
    [Test]
    procedure AccessorAncestorsFromIndex;
    [Test]
    procedure AccessorOptions;
    [Test]
    procedure WriteOnlyReported;
    [Test]
    procedure WriteOnlyFix;
    [Test]
    procedure WriteOnlySilentCases;
    [Test]
    procedure WriteOnlyOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Properties,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit einer Klasse TKunde aus AMembers; ABodies im implementation-Teil.</summary>
function Kunden(const AMembers, ABodies: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10 + AMembers + '  end;'#10 +
    'implementation'#10 + ABodies + 'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TPropertyAccessorInvalidRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TPropertyAccessorInvalidRule.Create, ASource, AConfig, APath);
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

procedure Silent(const ASource: string);
begin
  TRuleAssert.Silent(TPropertyAccessorInvalidRule.Create, ASource);
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

{ TPropertyRulesTests }

procedure TPropertyRulesTests.AccessorIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Kunden('  private'#10'    FName: string;'#10'  public'#10 +
    '    property Name: string read FName write SetName;'#10, '');
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('SetName ist in TKunde nicht deklariert (wie E2168).', Found[0].Message);
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(43, Found[0].Range.StartPos.Character);
  Assert.AreEqual(50, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('SetName anlegen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('procedure SetName(const Value: string);', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('procedure TKunde.SetName(const Value: string);', Fixed) > 0, Fixed);
  Silent(Fixed);
end;

procedure TPropertyRulesTests.AccessorValidFormsAreSilent;
begin
  Silent(Kunden('  private'#10'    FName: string;'#10'    FPunkt: TPunkt;'#10'    FListe: TArray<string>;'#10 +
    '    class var FAnzahl: Integer;'#10'    function GetItem(Index: Integer): string;'#10 +
    '    procedure SetItem(Index: Integer; const Value: string);'#10'    function GetFarbe(AIndex: Integer): Integer;'#10 +
    '    procedure SetFarbe(AIndex: Integer; Value: Integer);'#10'    class function GetZahl: Integer; static;'#10 +
    '    procedure SetName(const Value: string);'#10'    function GetZelle(X, Y: Integer): Double;'#10 +
    '  public'#10'    property Name: string read FName write SetName;'#10 +
    '    property Items[Index: Integer]: string read GetItem write SetItem; default;'#10 +
    '    property Zelle[X, Y: Integer]: Double read GetZelle;'#10 +
    '    property Rot: Integer index 1 read GetFarbe write SetFarbe;'#10 +
    '    class property Anzahl: Integer read FAnzahl write FAnzahl;'#10 +
    '    class property Zahl: Integer read GetZahl;'#10'    property X: Integer read FPunkt.X write FPunkt.X;'#10 +
    '    property Liste: TArray<string> read FListe;'#10'    property Langer: Longint read FAnzahlLokal;'#10,
    '').Replace('  TKunde = class', '  TPunkt = record'#10'    X, Y: Integer;'#10'  end;'#10'  TKunde = class')
    .Replace('    class var FAnzahl', '    FAnzahlLokal: Integer;'#10'    class var FAnzahl'));
  // Geerbte Mitglieder, Properties ohne Typ und eine Kette, die nicht bis TObject reicht.
  Silent('unit Kunden;'#10'interface'#10'type'#10'  TBasis = class'#10'  protected'#10'    FWert: Integer;'#10 +
    '    function GetWert: Integer; virtual;'#10'    property Wert: Integer read GetWert;'#10'  end;'#10 +
    '  TKunde = class(TBasis)'#10'  published'#10'    property Wert;'#10'    property Roh: Integer read FWert;'#10 +
    '    property Anders: Integer read GetWert;'#10'  end;'#10'  TFremd = class(TUnbekannt)'#10 +
    '    property Name: string read FName write SetName;'#10'  end;'#10'implementation'#10'end.');
  // Generische Klassen: Typparameter passen zu allem.
  Silent('unit Kunden;'#10'interface'#10'type'#10'  TBox<T> = class'#10'  private'#10'    FWert: T;'#10 +
    '    function GetWert: T;'#10'    procedure SetWert(const Value: T);'#10'  public'#10 +
    '    property Wert: T read GetWert write SetWert;'#10'  end;'#10'implementation'#10'end.');
  // Bedingte Mitglieder und Include-Dateien: keine Aussage.
  Silent(Kunden('  private'#10'    {$IFDEF DEBUG}'#10'    FSpur: string;'#10'    {$ENDIF}'#10 +
    '  public'#10'    property Spur: string read FSpur;'#10, ''));
  Silent(Kunden('  private'#10'    {$I KundeFelder.inc}'#10'  public'#10'    property Spur: string read FSpur;'#10, ''));
end;

procedure TPropertyRulesTests.AccessorMissingFixes;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  // Fehlender Getter und fehlendes Feld: Korrektur nach der Konvention.
  Source := Kunden('  public'#10'    property Name: string read GetName;'#10, '');
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('GetName ist in TKunde nicht deklariert (wie E2168).', Found[0].Message);
  Assert.AreEqual('GetName anlegen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('function GetName: string;', Fixed) > 0, Fixed);
  Silent(Fixed);
  Source := Kunden('  public'#10'    property Wert: Integer read FWert;'#10, '');
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('FWert anlegen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('FWert: Integer;', Fixed) > 0, Fixed);
  Silent(Fixed);
  // Indexparameter und index-Angabe wandern in den Getter.
  Source := Kunden('  public'#10'    property Items[I: Integer]: string read GetItems;'#10, '');
  Found := Findings(Source);
  Assert.AreEqual('GetItems anlegen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('function GetItems(I: Integer): string;', Fixed) > 0, Fixed);
  Silent(Fixed);
  // Andere Namen und Klassen-Properties: Meldung ohne Korrektur.
  Found := Findings(Kunden('  public'#10'    property Name: string read LiesName;'#10, ''));
  Assert.AreEqual('LiesName ist in TKunde nicht deklariert (wie E2168).', Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  Found := Findings(Kunden('  public'#10'    class property Anzahl: Integer read FAnzahl;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TPropertyRulesTests.AccessorWrongKinds;
begin
  Assert.AreEqual('Basis ist eine Property; hinter read gehört ein Feld oder eine Methode (wie E2168).',
    OnlyMessage(Kunden('  private'#10'    FBasis: Integer;'#10'  public'#10 +
    '    property Basis: Integer read FBasis;'#10'    property Kopie: Integer read Basis;'#10, '')));
  Assert.AreEqual('Die Array-Property Items braucht hinter read eine Methode; FItems ist ein Feld (wie E2174).',
    OnlyMessage(Kunden('  private'#10'    FItems: string;'#10'  public'#10 +
    '    property Items[Index: Integer]: string read FItems;'#10, '')));
  Assert.AreEqual('Die Property Rot hat eine index-Angabe und braucht hinter read eine Methode; FRot ist ein Feld ' +
    '(wie E2174).', OnlyMessage(Kunden('  private'#10'    FRot: Integer;'#10'  public'#10 +
    '    property Rot: Integer index 1 read FRot;'#10, '')));
  Assert.AreEqual('GetName ist überladen; Getter und Setter einer Property dürfen nicht überladen sein (wie E2271).',
    OnlyMessage(Kunden('  private'#10'    function GetName: string; overload;'#10 +
    '    function GetName(A: Integer): string; overload;'#10'  public'#10'    property Name: string read GetName;'#10,
    '')));
  Assert.AreEqual('Der Setter SetName nimmt den Wert als var-Parameter; ein Setter braucht einen Wert- oder ' +
    'const-Parameter (wie E2282).', OnlyMessage(Kunden('  private'#10'    FName: string;'#10 +
    '    procedure SetName(var Value: string);'#10'  public'#10'    property Name: string read FName write SetName;'#10,
    '')));
end;

procedure TPropertyRulesTests.AccessorSignatures;
begin
  Assert.AreEqual('GetName passt nicht als Getter von Name; erwartet wird function GetName: string (wie E2234).',
    OnlyMessage(Kunden('  private'#10'    procedure GetName;'#10'  public'#10'    property Name: string read GetName;'#10,
    '')));
  Assert.AreEqual('GetName passt nicht als Getter von Name; erwartet wird function GetName: string (wie E2234).',
    OnlyMessage(Kunden('  private'#10'    function GetName: Integer;'#10'  public'#10 +
    '    property Name: string read GetName;'#10, '')));
  // Indexparameter fehlt.
  Assert.AreEqual('GetItem passt nicht als Getter von Items; erwartet wird function GetItem(Index: Integer): string ' +
    '(wie E2234).', OnlyMessage(Kunden('  private'#10'    function GetItem: string;'#10'  public'#10 +
    '    property Items[Index: Integer]: string read GetItem;'#10, '')));
  Assert.AreEqual('GetRot passt nicht als Getter von Rot; erwartet wird function GetRot(AIndex: Integer): Integer ' +
    '(wie E2234).', OnlyMessage(Kunden('  private'#10'    function GetRot: Integer;'#10'  public'#10 +
    '    property Rot: Integer index 1 read GetRot;'#10, '')));
  Assert.AreEqual('SetName passt nicht als Setter von Name; erwartet wird procedure SetName(const Value: string) ' +
    '(wie E2234).', OnlyMessage(Kunden('  private'#10'    FName: string;'#10 +
    '    procedure SetName(const Value: Integer);'#10'  public'#10 +
    '    property Name: string read FName write SetName;'#10, '')));
  Assert.AreEqual('SetName passt nicht als Setter von Name; erwartet wird procedure SetName(const Value: string) ' +
    '(wie E2234).', OnlyMessage(Kunden('  private'#10'    FName: string;'#10'    function SetName: string;'#10 +
    '  public'#10'    property Name: string read FName write SetName;'#10, '')));
  // Unbekannte Typen (Alias aus einer anderen Unit): keine Aussage.
  Silent(Kunden('  private'#10'    function GetBetrag: TBetrag;'#10'  public'#10 +
    '    property Betrag: Currency read GetBetrag;'#10, ''));
end;

procedure TPropertyRulesTests.AccessorClassAndInstance;
begin
  Assert.AreEqual('Die Klassen-Property Anzahl braucht hinter read eine class var oder eine class-Methode mit ' +
    'static; FAnzahl ist ein Instanzfeld (wie E2355).', OnlyMessage(Kunden('  private'#10'    FAnzahl: Integer;'#10 +
    '  public'#10'    class property Anzahl: Integer read FAnzahl;'#10, '')));
  Assert.AreEqual('Die Klassen-Property Anzahl braucht hinter read eine class var oder eine class-Methode mit ' +
    'static; GetAnzahl ist eine Instanzmethode (wie E2355).', OnlyMessage(Kunden('  private'#10 +
    '    function GetAnzahl: Integer;'#10'  public'#10'    class property Anzahl: Integer read GetAnzahl;'#10, '')));
  Assert.AreEqual('Die Klassen-Property Anzahl braucht eine class-Methode mit static; GetAnzahl ist nicht static ' +
    '(wie E2355).', OnlyMessage(Kunden('  private'#10'    class function GetAnzahl: Integer;'#10'  public'#10 +
    '    class property Anzahl: Integer read GetAnzahl;'#10, '')));
  Assert.AreEqual('FAnzahl ist eine class var; die Property Anzahl braucht ein Instanzfeld oder eine Instanzmethode ' +
    '(wie E2356).', OnlyMessage(Kunden('  private'#10'    class var FAnzahl: Integer;'#10'  public'#10 +
    '    property Anzahl: Integer read FAnzahl;'#10, '')));
  Assert.AreEqual('GetAnzahl ist eine Klassenmethode; die Property Anzahl braucht ein Instanzfeld oder eine ' +
    'Instanzmethode (wie E2356).', OnlyMessage(Kunden('  private'#10'    class function GetAnzahl: Integer; static;'#10 +
    '  public'#10'    property Anzahl: Integer read GetAnzahl;'#10, '')));
end;

procedure TPropertyRulesTests.AccessorFieldSelectors;
var
  Types: string;
begin
  Types := 'unit Kunden;'#10'interface'#10'type'#10'  TPunkt = record'#10'    X, Y: Integer;'#10 +
    '    function Laenge: Double;'#10'  end;'#10'  TAdresse = class'#10'    Ort: string;'#10'  end;'#10 +
    '  TKunde = class'#10'  private'#10'    FPunkt: TPunkt;'#10'    FAdresse: TAdresse;'#10'  public'#10;
  Assert.AreEqual('FAdresse ist vom Typ TAdresse, keinem Record; ein Feldselektor wie FAdresse.Ort geht nur über ' +
    'ein Record-Feld (wie E2459).', OnlyMessage(Types + '    property Ort: string read FAdresse.Ort;'#10'  end;'#10 +
    'implementation'#10'end.'));
  Assert.AreEqual('TPunkt hat kein Feld Z (wie E2562).', OnlyMessage(Types +
    '    property Z: Integer read FPunkt.Z;'#10'  end;'#10'implementation'#10'end.'));
  Assert.AreEqual('TPunkt.Laenge ist kein Instanzfeld; hinter dem Punkt muss ein Feld des Records stehen ' +
    '(wie E2461).', OnlyMessage(Types + '    property Laenge: Double read FPunkt.Laenge;'#10'  end;'#10 +
    'implementation'#10'end.'));
  Silent(Types + '    property Y: Integer read FPunkt.Y write FPunkt.Y;'#10'  end;'#10'implementation'#10'end.');
end;

procedure TPropertyRulesTests.AccessorAncestorsFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
  Source: string;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Index.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TBasis = class'#10 +
    '  private'#10'    FGeheim: Integer;'#10'  protected'#10'    FWert: Integer;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\Projekt\Basis.pas', nil));
  Source := 'unit Kunden;'#10'interface'#10'uses'#10'  Basis;'#10'type'#10'  TKunde = class(TBasis)'#10 +
    '  public'#10'    property Wert: Integer read FWert;'#10'    property Geheim: Integer read FGeheim;'#10 +
    '    property Fehlt: Integer read FFehlt;'#10'  end;'#10'implementation'#10'end.';
  Found := TRuleAssert.IndexFindings(TPropertyAccessorInvalidRule.Create, Source, Index, '', '');
  // FWert ist geerbt, FGeheim privat in einer anderen Unit (keine Aussage), FFehlt fehlt in der ganzen Kette.
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('FFehlt ist in TKunde nicht deklariert (wie E2168).', Found[0].Message);
end;

procedure TPropertyRulesTests.AccessorOptions;
var
  Source: string;
begin
  Source := Kunden('  public'#10'    property Name: string read GetName;'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"property-accessor-invalid": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"property-accessor-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"property-accessor-invalid": {"exclude": ["Alt/*.pas"]}}}', 'Source/Kunden.pas'))));
end;

function WriteOnly(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TWriteOnlyPropertyRule.Create, ASource);
end;

function WriteOnly(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TWriteOnlyPropertyRule.Create, ASource, AConfig);
end;

procedure TPropertyRulesTests.WriteOnlyReported;
var
  Found: TArray<TRuleFinding>;
begin
  Assert.IsFalse(TWriteOnlyPropertyRule.Create.Descriptor.Experimental, 'Standard an');
  Found := WriteOnly(Kunden('  private'#10'    procedure SetPasswort(const Value: string);'#10'  public'#10 +
    '    property Passwort: string write SetPasswort;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Property Passwort hat kein read.', Found[0].Message);
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(13, Found[0].Range.StartPos.Character);
  // Ohne passendes Feld keine Korrektur.
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // Auch Array-Properties, Interfaces und Klassen-Properties.
  Assert.AreEqual(3, Integer(Length(WriteOnly('unit U;'#10'interface'#10'type'#10'  IKunde = interface'#10 +
    '    procedure SetName(const Value: string);'#10'    property Name: string write SetName;'#10'  end;'#10 +
    '  TListe = class'#10'    property Werte[I: Integer]: string write SetWert;'#10 +
    '    class property Zaehler: Integer write FZaehler;'#10'  end;'#10'implementation'#10'end.'))));
end;

procedure TPropertyRulesTests.WriteOnlyFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Kunden('  private'#10'    FPasswort: string;'#10'    procedure SetPasswort(const Value: string);'#10 +
    '  public'#10'    property Passwort: string write SetPasswort;'#10, '');
  Found := WriteOnly(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('read FPasswort ergänzen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(StringReplace(Source, 'string write', 'string read FPasswort write', []), Fixed);
  TRuleAssert.Silent(TWriteOnlyPropertyRule.Create, Fixed);
  // Feld mit anderem Typ: keine Korrektur.
  Source := StringReplace(Source, 'FPasswort: string;', 'FPasswort: TBytes;', []);
  Assert.AreEqual(0, Integer(Length(WriteOnly(Source)[0].Fixes)));
end;

procedure TPropertyRulesTests.WriteOnlySilentCases;
begin
  // read vorhanden, neu veröffentlichte Property ohne Typ, Property ohne read und write.
  TRuleAssert.Silent(TWriteOnlyPropertyRule.Create, Kunden('  public'#10 +
    '    property Name: string read FName write FName;'#10'    property Caption write SetCaption;'#10 +
    '    property Tag;'#10'    property Lesen: Integer read FLesen;'#10, ''));
end;

procedure TPropertyRulesTests.WriteOnlyOptions;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Kunden('  public'#10'    [Geheim]'#10'    property Passwort: string write SetPasswort;'#10 +
    '    [Schluessel(1), GeheimAttribute]'#10'    property Pin: string write SetPin;'#10, '');
  Assert.AreEqual(2, Integer(Length(WriteOnly(Source))));
  Assert.AreEqual(0, Integer(Length(WriteOnly(Source,
    '{"rules": {"write-only-property": {"allowAttributes": ["GeheimAttribute"]}}}'))));
  Assert.AreEqual(1, Integer(Length(WriteOnly(Source,
    '{"rules": {"write-only-property": {"allowAttributes": ["Schluessel"]}}}'))));
  Assert.AreEqual(0, Integer(Length(WriteOnly(Source, '{"rules": {"write-only-property": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TWriteOnlyPropertyRule.Create, Source,
    '{"rules": {"write-only-property": {"exclude": ["Alt/**"]}}}', 'Alt/Kunden.pas'))));
  TConfigurationParser.Parse('{"rules": {"write-only-property": {"allowAttributes": "Geheim"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowAttributes" muss eine Liste von Texten sein', Issues[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TPropertyRulesTests);

end.
