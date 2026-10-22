unit Atlas.Common.Rules.Builtin.MemberHiding.Tests;

// Tests der Regel member-hides-ancestor (#1003) aus Rules.Builtin.Inheritance:
// Felder, Properties und nicht virtuelle Methoden, die gleichnamige Member
// eines Vorfahren verdecken, Sichtbarkeit, Vorfahren aus dem Index,
// Korrektur und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMemberHidingRulesTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure PropertyHidesField;
    [Test]
    procedure MethodHidesStaticMethod;
    [Test]
    procedure SilentCases;
    [Test]
    procedure VisibilityAndIndex;
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
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit TBasis (ABase) und TKunde = class(TBasis) (AOwn); ABodies im implementation-Teil.</summary>
function Kunden(const ABase, AOwn, ABodies: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'type'#10'  TBasis = class'#10 + ABase + '  end;'#10 +
    '  TKunde = class(TBasis)'#10 + AOwn + '  end;'#10'implementation'#10 + ABodies + 'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TMemberHidesAncestorRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TMemberHidesAncestorRule.Create, ASource, AConfig, APath);
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
  TRuleAssert.Silent(TMemberHidesAncestorRule.Create, ASource);
end;

/// <summary>Wendet Edits an, die jeweils innerhalb einer Zeile liegen (Zeilen aus #10), von hinten nach vorn.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Lines: TArray<string>;
  Index: Integer;
  Edit: TRuleEdit;
begin
  Lines := AText.Split([#10]);
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Lines[Edit.Range.StartPos.Line] := Copy(Lines[Edit.Range.StartPos.Line], 1, Edit.Range.StartPos.Character) +
      Edit.NewText + Copy(Lines[Edit.Range.StartPos.Line], Edit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, Lines);
end;

{ TMemberHidingRulesTests }

procedure TMemberHidingRulesTests.IssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Kunden('    FName: string;'#10, '    FName: string;'#10'    procedure Setzen;'#10,
    'procedure TKunde.Setzen;'#10'begin'#10'  FName := ''A'';'#10'  Self.FName := ''B'';'#10 +
    '  TBasis(Self).FName := ''C'';'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('FName verdeckt TBasis.FName (wie W1009).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In FKundeName umbenennen (in dieser Unit)', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Kunden('    FName: string;'#10, '    FKundeName: string;'#10'    procedure Setzen;'#10,
    'procedure TKunde.Setzen;'#10'begin'#10'  FKundeName := ''A'';'#10'  Self.FKundeName := ''B'';'#10 +
    '  TBasis(Self).FName := ''C'';'#10'end;'#10), Fixed);
  Silent(Fixed);
end;

procedure TMemberHidingRulesTests.PropertyHidesField;
begin
  Assert.AreEqual('Wert verdeckt TBasis.Wert (wie W1009).', OnlyMessage(Kunden('    Wert: Integer;'#10,
    '  private'#10'    FText: string;'#10'  public'#10'    property Wert: string read FText;'#10, '')));
  Assert.AreEqual('FAnzahl verdeckt TBasis.FAnzahl (wie W1009).', OnlyMessage(Kunden('  private'#10 +
    '    FZahl: Integer;'#10'  public'#10'    property FAnzahl: Integer read FZahl;'#10, '    FAnzahl: Integer;'#10,
    '')));
end;

procedure TMemberHidingRulesTests.MethodHidesStaticMethod;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Kunden('    procedure Speichern(const APfad: string);'#10,
    '    procedure Speichern(const APfad: string);'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Speichern verdeckt TBasis.Speichern (wie W1009).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Found[0].Confidence));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TMemberHidingRulesTests.SilentCases;
begin
  // Andere Signatur, overload, reintroduce, virtuelle Methoden (hides-virtual), Konstruktoren, Klassenmethoden.
  Silent(Kunden('    procedure Speichern(const APfad: string);'#10'    procedure Laden;'#10 +
    '    procedure Pruefen;'#10'    procedure Zeigen; virtual;'#10'    constructor Create;'#10 +
    '    class function Neu: TBasis;'#10'    procedure Melden;'#10,
    '    procedure Speichern(const APfad: string; AFormat: Integer);'#10'    procedure Laden; overload;'#10 +
    '    procedure Pruefen; reintroduce;'#10'    procedure Zeigen;'#10'    constructor Create;'#10 +
    '    class function Neu: TBasis;'#10'    procedure Melden; virtual;'#10, ''));
  // Neu veröffentlichte und neu typisierte Properties.
  Silent(Kunden('  protected'#10'    property Caption: string read GetCaption;'#10,
    '  published'#10'    property Caption;'#10, ''));
  Silent(Kunden('    property Wert: Integer read GetWert;'#10, '    property Wert: string read GetText;'#10, ''));
  // Nur im Nachfahren, nur im Vorfahren.
  Silent(Kunden('    FAlt: Integer;'#10, '    FNeu: Integer;'#10, ''));
end;

procedure TMemberHidingRulesTests.VisibilityAndIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
  Source: string;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TFern = class'#10 +
    '  private'#10'    FGeheim: Integer;'#10'  strict private'#10'    FStreng: Integer;'#10'  protected'#10 +
    '    FWert: Integer;'#10'  end;'#10'implementation'#10'end.', 'C:\Projekt\Basis.pas', nil));
  Source := 'unit Kunden;'#10'interface'#10'uses'#10'  Basis;'#10'type'#10'  TKunde = class(TFern)'#10 +
    '    FGeheim: Integer;'#10'    FStreng: Integer;'#10'    FWert: Integer;'#10'  end;'#10'implementation'#10'end.';
  Found := TRuleAssert.IndexFindings(TMemberHidesAncestorRule.Create, Source, Index, '', '');
  // private einer anderen Unit sieht TKunde nicht; strict private nur mit ignoreStrictPrivate = false.
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('FWert verdeckt TFern.FWert (wie W1009).', Found[0].Message);
  // private derselben Unit ist sichtbar.
  Assert.AreEqual('FGeheim verdeckt TBasis.FGeheim (wie W1009).', OnlyMessage(Kunden('  private'#10 +
    '    FGeheim: Integer;'#10, '    FGeheim: Integer;'#10, '')));
  Silent(Kunden('  strict private'#10'    FStreng: Integer;'#10, '    FStreng: Integer;'#10, ''));
end;

procedure TMemberHidingRulesTests.Options;
var
  Source: string;
begin
  Source := Kunden('    FName: string;'#10, '    FName: string;'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"member-hides-ancestor": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"member-hides-ancestor": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunden.pas'))));
  Source := Kunden('  strict private'#10'    FStreng: Integer;'#10, '    FStreng: Integer;'#10, '');
  Assert.AreEqual(0, Integer(Length(Findings(Source, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"member-hides-ancestor": {"ignoreStrictPrivate": false}}}', 'Source/Kunden.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TMemberHidingRulesTests);

end.
