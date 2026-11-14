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
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(mFound)), ASource);
  Result := mFound[0].Message;
end;

procedure Silent(const ASource: string);
begin
  TRuleAssert.Silent(TMemberHidesAncestorRule.Create, ASource);
end;

/// <summary>Wendet Edits an, die jeweils innerhalb einer Zeile liegen (Zeilen aus #10), von hinten nach vorn.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mEdit: TRuleEdit;
begin
  mLines := AText.Split([#10]);
  for mIndex := High(AFix.Edits) downto 0 do
  begin
    mEdit := AFix.Edits[mIndex];
    mLines[mEdit.Range.StartPos.Line] := Copy(mLines[mEdit.Range.StartPos.Line], 1, mEdit.Range.StartPos.Character) +
      mEdit.NewText + Copy(mLines[mEdit.Range.StartPos.Line], mEdit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, mLines);
end;

{ TMemberHidingRulesTests }

procedure TMemberHidingRulesTests.IssueExample;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Kunden('    FName: string;'#10, '    FName: string;'#10'    procedure Setzen;'#10,
    'procedure TKunde.Setzen;'#10'begin'#10'  FName := ''A'';'#10'  Self.FName := ''B'';'#10 +
    '  TBasis(Self).FName := ''C'';'#10'end;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('FName verdeckt TBasis.FName.', mFound[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
  Assert.AreEqual(7, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('In FKundeName umbenennen (in dieser Unit)', mFound[0].Fixes[0].Title);
  mFixed := ApplyFix(mSource, mFound[0].Fixes[0]);
  Assert.AreEqual(Kunden('    FName: string;'#10, '    FKundeName: string;'#10'    procedure Setzen;'#10,
    'procedure TKunde.Setzen;'#10'begin'#10'  FKundeName := ''A'';'#10'  Self.FKundeName := ''B'';'#10 +
    '  TBasis(Self).FName := ''C'';'#10'end;'#10), mFixed);
  Silent(mFixed);
end;

procedure TMemberHidingRulesTests.PropertyHidesField;
begin
  Assert.AreEqual('Wert verdeckt TBasis.Wert (wie W1009).', OnlyMessage(Kunden('    Wert: Integer;'#10,
    '  private'#10'    FText: string;'#10'  public'#10'    property Wert: string read FText;'#10, '')));
  // Feld über Property: gemeldet, aber ohne Code; Delphi 13 meldet W1009 nur für Property über Feld (#1383).
  Assert.AreEqual('FAnzahl verdeckt TBasis.FAnzahl.', OnlyMessage(Kunden('  private'#10 +
    '    FZahl: Integer;'#10'  public'#10'    property FAnzahl: Integer read FZahl;'#10, '    FAnzahl: Integer;'#10,
    '')));
end;

procedure TMemberHidingRulesTests.MethodHidesStaticMethod;
var
  mFound: TArray<TRuleFinding>;
begin
  // Niedrige Konfidenz: dcc schweigt, und in der FP-Prüfung vom 28.10.2026 war das meist gewollt.
  mFound := Findings(Kunden('    procedure Speichern(const APfad: string);'#10,
    '    procedure Speichern(const APfad: string);'#10, ''), '{"minConfidence": "low"}', 'Kunden.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Speichern verdeckt TBasis.Speichern.', mFound[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFound[0].Confidence));
  Assert.AreEqual(0, Integer(Length(Findings(Kunden('    procedure Speichern(const APfad: string);'#10,
    '    procedure Speichern(const APfad: string);'#10, '')))));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
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
  mIndex: ISymbolIndex;
  mFound: TArray<TRuleFinding>;
  mSource: string;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TFern = class'#10 +
    '  private'#10'    FGeheim: Integer;'#10'  strict private'#10'    FStreng: Integer;'#10'  protected'#10 +
    '    FWert: Integer;'#10'  end;'#10'implementation'#10'end.', 'C:\Projekt\Basis.pas', nil));
  mSource := 'unit Kunden;'#10'interface'#10'uses'#10'  Basis;'#10'type'#10'  TKunde = class(TFern)'#10 +
    '    FGeheim: Integer;'#10'    FStreng: Integer;'#10'    FWert: Integer;'#10'  end;'#10'implementation'#10'end.';
  mFound := TRuleAssert.IndexFindings(TMemberHidesAncestorRule.Create, mSource, mIndex, '', '');
  // private einer anderen Unit sieht TKunde nicht; strict private nur mit ignoreStrictPrivate = false.
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('FWert verdeckt TFern.FWert.', mFound[0].Message);
  // private derselben Unit ist sichtbar.
  Assert.AreEqual('FGeheim verdeckt TBasis.FGeheim.', OnlyMessage(Kunden('  private'#10 +
    '    FGeheim: Integer;'#10, '    FGeheim: Integer;'#10, '')));
  Silent(Kunden('  strict private'#10'    FStreng: Integer;'#10, '    FStreng: Integer;'#10, ''));
end;

procedure TMemberHidingRulesTests.Options;
var
  mSource: string;
begin
  mSource := Kunden('    FName: string;'#10, '    FName: string;'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"member-hides-ancestor": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": "off"}}', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource,
    '{"rules": {"member-hides-ancestor": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunden.pas'))));
  mSource := Kunden('  strict private'#10'    FStreng: Integer;'#10, '    FStreng: Integer;'#10, '');
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(mSource,
    '{"rules": {"member-hides-ancestor": {"ignoreStrictPrivate": false}}}', 'Source/Kunden.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TMemberHidingRulesTests);

end.
