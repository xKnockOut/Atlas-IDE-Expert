unit Atlas.Common.Rules.Builtin.FreeFields.Tests;

// Tests für field-not-freed (bis #918 owned-field-not-freed) und
// owned-field-free-unclear (#666): Beispiel aus #918, Owner-Komponenten,
// Option ignoreTypes, frühere Kennung, Abschalten und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFreeFieldRulesTests = class
  public
    [Test]
    procedure NotFreedIsWarningWithFix;
    [Test]
    procedure FreeAndNilStyleInFix;
    [Test]
    procedure UnclearIsHintWithoutFix;
    [Test]
    procedure SwitchedOff;
    [Test]
    procedure IssueExampleReportsOnlyUnfreedField;
    [Test]
    procedure OwnedComponentAndFreedFieldSilent;
    [Test]
    procedure IgnoreTypesSilencesClass;
    [Test]
    procedure FormerIdStillApplies;
    [Test]
    procedure OffAndExcludeSilence;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Editing.FreeFields,
  Atlas.Common.Rules.Builtin.FreeFields,
  Atlas.Tests.RuleAssert;

const
  Text = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FList: TStringList;'#10 +
    '  public'#10'    constructor Create;'#10'  end;'#10'implementation'#10'constructor TFoo.Create;'#10'begin'#10 +
    '  FList := TStringList.Create;'#10'end;'#10'end.';
  Returned = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FList: TStringList;'#10 +
    '  public'#10'    constructor Create;'#10'    function Take: TStringList;'#10'  end;'#10'implementation'#10 +
    'constructor TFoo.Create;'#10'begin'#10'  FList := TStringList.Create;'#10'end;'#10 +
    'function TFoo.Take: TStringList;'#10'begin'#10'  Result := FList;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.NotFreedIsWarningWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Text);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('FList wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben (Speicherleck).',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Im Destruktor freigeben', Findings[0].Fixes[0].Title);
  Assert.IsFalse(Findings[0].Fixes[0].Safe);
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes[0].Edits)));
  Assert.AreEqual(#10'    destructor Destroy; override;', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.IsTrue(Findings[0].Fixes[0].Edits[1].NewText.Contains('  FList.Free;'#10'  inherited;'));
  TRuleAssert.Silent(TOwnedFieldFreeUnclearRule.Create, Text);
end;

procedure TFreeFieldRulesTests.FreeAndNilStyleInFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Text,
    '{"refactoring": {"freeFieldsStyle": "freeAndNil"}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Findings[0].Fixes[0].Edits[1].NewText.Contains('  FreeAndNil(FList);'#10'  inherited;'));
end;

procedure TFreeFieldRulesTests.UnclearIsHintWithoutFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldFreeUnclearRule.Create, Returned);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('"FList" wird in TFoo.Create erzeugt und nicht freigegeben; ob TFoo es freigeben muss, ist unklar: ' +
    'Es wird von TFoo.Take zurückgegeben', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, Returned);
end;

procedure TFreeFieldRulesTests.SwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Text,
    '{"refactoring": {"freeFields": false}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldFreeUnclearRule.Create, Returned,
    '{"refactoring": {"freeFields": false}}'))));
end;

const
  Import = 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FZeilen: TStringList;'#10 +
    '    FFehler: TStringList;'#10'  public'#10'    constructor Create;'#10'    destructor Destroy; override;'#10 +
    '  end;'#10'implementation'#10'constructor TImport.Create;'#10'begin'#10'  FZeilen := TStringList.Create;'#10 +
    '  FFehler := TStringList.Create;'#10'end;'#10'destructor TImport.Destroy;'#10'begin'#10'  FZeilen.Free;'#10 +
    '  inherited;'#10'end;'#10'end.';

procedure TFreeFieldRulesTests.IssueExampleReportsOnlyUnfreedField;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FFehler wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben (Speicherleck).',
    Findings[0].Message);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  // Korrigierte Form: beide Felder frei.
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, StringReplace(Import, '  FZeilen.Free;'#10,
    '  FZeilen.Free;'#10'  FFehler.Free;'#10, []));
end;

procedure TFreeFieldRulesTests.OwnedComponentAndFreedFieldSilent;
const
  Owned = 'unit U;'#10'interface'#10'type'#10'  TFenster = class(TForm)'#10'  private'#10 +
    '    FKnopf: TButton;'#10'  public'#10'    constructor Create(AOwner: TComponent); override;'#10'  end;'#10 +
    'implementation'#10'constructor TFenster.Create(AOwner: TComponent);'#10'begin'#10 +
    '  inherited Create(AOwner);'#10'  FKnopf := TButton.Create(Self);'#10'end;'#10'end.';
begin
  // Komponente mit Owner: der Owner gibt sie frei.
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, Owned);
end;

procedure TFreeFieldRulesTests.IgnoreTypesSilencesClass;
var
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
  Field: TOwnedField;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"ignoreTypes": ["TStringList"]}}}', 'U.pas'))));
  Findings := TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"ignoreTypes": ["TObjectList"]}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)), 'andere Klasse bleibt gemeldet');
  // Generische Deklaration trifft auch ohne Typparameter.
  Field := Default(TOwnedField);
  Field.TypeName := 'TObjectList<TOrder>';
  Field.CreatedType := 'TObjectList<TOrder>';
  Assert.IsTrue(TOwnedFieldNotFreedRule.Ignored(Field, ['tobjectlist']));
  Assert.IsFalse(TOwnedFieldNotFreedRule.Ignored(Field, ['TStringList']));
  TConfigurationParser.Parse('{"rules": {"field-not-freed": {"ignoreTypes": "TStringList"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"ignoreTypes" muss eine Liste von Texten sein', Issues[0].Message);
end;

procedure TFreeFieldRulesTests.FormerIdStillApplies;
begin
  Assert.AreEqual('field-not-freed', TRuleIdAliases.Current('owned-field-not-freed'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"owned-field-not-freed": "off"}}', 'U.pas'))));
  TRuleAssert.Silent(TOwnedFieldNotFreedRule.Create, StringReplace(Import, '    FFehler: TStringList;',
    '    FFehler: TStringList; // lsp-ignore: owned-field-not-freed', []));
end;

procedure TFreeFieldRulesTests.OffAndExcludeSilence;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOwnedFieldNotFreedRule.Create, Import,
    '{"rules": {"field-not-freed": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldRulesTests);

end.
