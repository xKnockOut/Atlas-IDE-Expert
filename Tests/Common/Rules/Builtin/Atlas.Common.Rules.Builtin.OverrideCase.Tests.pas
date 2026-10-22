unit Atlas.Common.Rules.Builtin.OverrideCase.Tests;

// Tests der Regel override-case-mismatch (#1021) aus Rules.Builtin.Inheritance:
// Schreibweise überschriebener Methoden (H2365), geringere Sichtbarkeit
// (H2269), Schreibweise von Getter und Setter (H2367), inline-Methoden mit
// Zugriff auf weniger sichtbare Mitglieder (H2440), Korrekturen und
// Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOverrideCaseRulesTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure CaseOfLocalAncestor;
    [Test]
    procedure SilentOverrides;
    [Test]
    procedure LowerVisibility;
    [Test]
    procedure AccessorCase;
    [Test]
    procedure InlineAccessesLowerVisibility;
    [Test]
    procedure InlineSilentCases;
    [Test]
    procedure Options;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Tests.RuleAssert;

const
  /// <summary>Die Regel ist ohne Eintrag in atlas.json aus.</summary>
  Enabled = '{"rules": {"override-case-mismatch": "hint"}}';

/// <summary>Unit mit TBasis (ABase) und TKunde = class(TBasis) (AOwn) im interface-Teil; ABodies danach.</summary>
function Kunden(const ABase, AOwn, ABodies: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'type'#10'  TBasis = class'#10 + ABase + '  end;'#10 +
    '  TKunde = class(TBasis)'#10 + AOwn + '  end;'#10'implementation'#10 + ABodies + 'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TOverrideCaseMismatchRule.Create, ASource, Enabled, '');
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TOverrideCaseMismatchRule.Create, ASource, AConfig, APath);
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

/// <summary>Wendet Edits an, die jeweils innerhalb einer Zeile liegen (Zeilen aus #10), von hinten nach vorn.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Lines: TArray<string>;
  Index, Later: Integer;
  Edit: TRuleEdit;
  Edits: TArray<TRuleEdit>;
begin
  // Nach Position absteigend, damit frühere Edits die Spalten späterer nicht verschieben.
  Edits := Copy(AFix.Edits);
  for Index := 0 to High(Edits) do
    for Later := Index + 1 to High(Edits) do
      if (Edits[Later].Range.StartPos.Line > Edits[Index].Range.StartPos.Line) or
        ((Edits[Later].Range.StartPos.Line = Edits[Index].Range.StartPos.Line) and
        (Edits[Later].Range.StartPos.Character > Edits[Index].Range.StartPos.Character)) then
      begin
        Edit := Edits[Index];
        Edits[Index] := Edits[Later];
        Edits[Later] := Edit;
      end;
  Lines := AText.Split([#10]);
  for Edit in Edits do
    Lines[Edit.Range.StartPos.Line] := Copy(Lines[Edit.Range.StartPos.Line], 1, Edit.Range.StartPos.Character) +
      Edit.NewText + Copy(Lines[Edit.Range.StartPos.Line], Edit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, Lines);
end;

{ TOverrideCaseRulesTests }

procedure TOverrideCaseRulesTests.IssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10'  public'#10 +
    '    destructor destroy; override;'#10'  end;'#10'implementation'#10'destructor TKunde.destroy;'#10'begin'#10 +
    '  inherited;'#10'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('Schreibweise weicht von TObject.Destroy ab (wie H2365).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(15, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Schreibweise vom Vorfahr übernehmen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual('unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10'  public'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'implementation'#10'destructor TKunde.Destroy;'#10'begin'#10 +
    '  inherited;'#10'end;'#10'end.', Fixed);
  Silent(Fixed);
end;

procedure TOverrideCaseRulesTests.CaseOfLocalAncestor;
begin
  Assert.AreEqual('Schreibweise weicht von TBasis.Zeichnen ab (wie H2365).',
    OnlyMessage(Kunden('    procedure Zeichnen(AFarbe: Integer); virtual;'#10,
    '    procedure zeichnen(AFarbe: Integer); override;'#10, '')));
end;

procedure TOverrideCaseRulesTests.SilentOverrides;
begin
  // Gleiche Schreibweise, Vorfahr unbekannt, keine override-Direktive, reintroduce.
  Silent(Kunden('    procedure Zeichnen; virtual;'#10'    procedure Laden; virtual;'#10,
    '    procedure Zeichnen; override;'#10'    procedure laden; reintroduce;'#10, ''));
  Silent('unit Kunden;'#10'interface'#10'type'#10'  TKunde = class(TFremd)'#10'    procedure zeichnen; override;'#10 +
    '  end;'#10'implementation'#10'end.');
  // Nur in einem inaktiven Zweig deklariert: keine Aussage.
  Silent(Kunden('  {$IFDEF ALT}'#10'    procedure Zeichnen; virtual;'#10'  {$ELSE}'#10 +
    '    procedure Zeichnen; dynamic;'#10'  {$ENDIF}'#10, '    procedure Zeichnen; override;'#10, ''));
end;

procedure TOverrideCaseRulesTests.LowerVisibility;
begin
  Assert.AreEqual('TKunde.Zeichnen ist protected und damit weniger sichtbar als TBasis.Zeichnen (public) ' +
    '(wie H2269).', OnlyMessage(Kunden('  public'#10'    procedure Zeichnen; virtual;'#10,
    '  protected'#10'    procedure Zeichnen; override;'#10, '')));
  Assert.AreEqual('TKunde.Destroy ist private und damit weniger sichtbar als TObject.Destroy (public) ' +
    '(wie H2269).', OnlyMessage('unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10'  private'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'implementation'#10'end.'));
  // Gleiche Stufe (protected und strict protected, public und published) und Klassen im implementation-Teil.
  Silent(Kunden('  protected'#10'    procedure Zeichnen; virtual;'#10'  public'#10'    procedure Laden; virtual;'#10,
    '  strict protected'#10'    procedure Zeichnen; override;'#10'  published'#10'    procedure Laden; override;'#10,
    ''));
  Silent('unit Kunden;'#10'interface'#10'implementation'#10'type'#10'  TKunde = class'#10'  private'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'end.');
end;

procedure TOverrideCaseRulesTests.AccessorCase;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Kunden('', '  private'#10'    function getName: string;'#10'    procedure SETNAME(const AWert: string);'#10 +
    '  public'#10'    property Name: string read getName write SETNAME;'#10,
    'function TKunde.getName: string;'#10'begin'#10'  Result := '''';'#10'end;'#10 +
    'procedure TKunde.SETNAME(const AWert: string);'#10'begin'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual(2, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('Die Zugriffsmethode TKunde.getName sollte TKunde.GetName geschrieben werden (wie H2367).',
    Found[0].Message);
  Assert.AreEqual('Die Zugriffsmethode TKunde.SETNAME sollte TKunde.SetName geschrieben werden (wie H2367).',
    Found[1].Message);
  Assert.AreEqual('In GetName umbenennen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Kunden('', '  private'#10'    function GetName: string;'#10 +
    '    procedure SETNAME(const AWert: string);'#10'  public'#10 +
    '    property Name: string read GetName write SETNAME;'#10,
    'function TKunde.GetName: string;'#10'begin'#10'  Result := '''';'#10'end;'#10 +
    'procedure TKunde.SETNAME(const AWert: string);'#10'begin'#10'end;'#10), Fixed);
  // Felder, richtige Schreibweise und andere Namen bleiben still.
  Silent(Kunden('', '  private'#10'    fName: string;'#10'    function GetWert: Integer;'#10 +
    '    function LiesText: string;'#10'  public'#10'    property Name: string read fName;'#10 +
    '    property Wert: Integer read GetWert;'#10'    property Text: string read LiesText;'#10, ''));
end;

procedure TOverrideCaseRulesTests.InlineAccessesLowerVisibility;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings('unit Zaehler;'#10'interface'#10'type'#10'  TZaehler = class'#10'  private'#10 +
    '    FAnzahl: Integer;'#10'    function Intern: Integer;'#10'  public'#10 +
    '    function Anzahl: Integer; inline;'#10'  end;'#10'implementation'#10 +
    'function TZaehler.Intern: Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10 +
    'function TZaehler.Anzahl: Integer;'#10'begin'#10'  Result := FAnzahl + Intern + Self.FAnzahl;'#10'end;'#10 +
    'end.');
  Assert.AreEqual(2, Integer(Length(Found)), Join(Found));
  Assert.AreEqual('Die inline-Methode TZaehler.Anzahl ist public, greift aber auf FAnzahl (private) zu; ' +
    'außerhalb der Klasse setzt der Compiler sie nicht ein (wie H2440).', Found[0].Message);
  Assert.AreEqual(17, Found[0].Range.StartPos.Line);
  Assert.AreEqual(12, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Die inline-Methode TZaehler.Anzahl ist public, greift aber auf Intern (private) zu; ' +
    'außerhalb der Klasse setzt der Compiler sie nicht ein (wie H2440).', Found[1].Message);
  // Auch in Records und für geerbte protected-Mitglieder.
  Assert.AreEqual('Die inline-Methode TPunkt.Summe ist public, greift aber auf FX (private) zu; außerhalb der ' +
    'Klasse setzt der Compiler sie nicht ein (wie H2440).', OnlyMessage('unit Punkte;'#10'interface'#10'type'#10 +
    '  TPunkt = record'#10'  private'#10'    FX: Integer;'#10'  public'#10'    function Summe: Integer; inline;'#10 +
    '  end;'#10'implementation'#10'function TPunkt.Summe: Integer;'#10'begin'#10'  Result := FX;'#10'end;'#10 +
    'end.'));
  Assert.AreEqual('Die inline-Methode TKunde.Lesen ist public, greift aber auf FWert (protected) zu; außerhalb ' +
    'der Klasse setzt der Compiler sie nicht ein (wie H2440).', OnlyMessage(Kunden('  protected'#10 +
    '    FWert: Integer;'#10, '  public'#10'    function Lesen: Integer; inline;'#10,
    'function TKunde.Lesen: Integer;'#10'begin'#10'  Result := FWert;'#10'end;'#10)));
end;

procedure TOverrideCaseRulesTests.InlineSilentCases;
begin
  // Gleiche Stufe, Parameter und lokale Variablen gleichen Namens, fremde Objekte, with, ohne inline.
  Silent('unit Zaehler;'#10'interface'#10'type'#10'  TZaehler = class'#10'  private'#10'    FAnzahl: Integer;'#10 +
    '    function Intern: Integer; inline;'#10'  public'#10'    Wert: Integer;'#10 +
    '    function Anzahl(FAnzahl: Integer): Integer; inline;'#10'    function Summe(AAnderer: TZaehler): Integer; ' +
    'inline;'#10'    function Mit: Integer; inline;'#10'    function Normal: Integer;'#10'    function Lokal: ' +
    'Integer; inline;'#10'  end;'#10'implementation'#10 +
    'function TZaehler.Intern: Integer;'#10'begin'#10'  Result := FAnzahl;'#10'end;'#10 +
    'function TZaehler.Anzahl(FAnzahl: Integer): Integer;'#10'begin'#10'  Result := FAnzahl + Wert;'#10'end;'#10 +
    'function TZaehler.Summe(AAnderer: TZaehler): Integer;'#10'begin'#10'  Result := AAnderer.FAnzahl;'#10'end;'#10 +
    'function TZaehler.Mit: Integer;'#10'begin'#10'  with Self do'#10'    Result := FAnzahl;'#10'end;'#10 +
    'function TZaehler.Normal: Integer;'#10'begin'#10'  Result := FAnzahl;'#10'end;'#10 +
    'function TZaehler.Lokal: Integer;'#10'var'#10'  Intern: Integer;'#10'begin'#10'  Intern := 1;'#10 +
    '  Result := Intern;'#10'end;'#10'end.');
end;

procedure TOverrideCaseRulesTests.Options;
var
  Source: string;
begin
  Source := 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10'  public'#10 +
    '    destructor destroy; override;'#10'  end;'#10'implementation'#10'end.';
  // Standard aus (#1021).
  Assert.IsTrue(TOverrideCaseMismatchRule.Create.Descriptor.Experimental);
  Assert.AreEqual(0, Integer(Length(Findings(Source, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source, Enabled, 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"override-case-mismatch": {"severity": "hint", "exclude": ["Source/*.pas"]}}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"override-case-mismatch": {"severity": "hint", "exclude": ["Alt/*.pas"]}}}',
    'Source/Kunden.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TOverrideCaseRulesTests);

end.
