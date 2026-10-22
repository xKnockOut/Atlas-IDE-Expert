unit Atlas.Common.Rules.Builtin.Recursion.Tests;

// Tests der Regel setter-recursion (#623, #910): Setter und Getter der
// eigenen Property als Fehler, Feld aus der Deklaration bzw. F<Name> als
// Korrektur, keine Meldung ohne Falle, Unterdrückung, Abschalten, Ausnahmen,
// frühere Kennung recursive-property-accessor und Registrierung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRecursionRulesTests = class
  public
    [Test]
    procedure SetterExampleIsErrorWithFieldFix;
    [Test]
    procedure GetterUsesFieldOfDeclaration;
    [Test]
    procedure SetterWithoutFieldHasNoFix;
    [Test]
    procedure FieldAccessIsSilent;
    [Test]
    procedure OtherPropertyIsSilent;
    [Test]
    procedure SuppressedByComment;
    [Test]
    procedure FormerIdStillSuppresses;
    [Test]
    procedure OffAndExcludeSilence;
    [Test]
    procedure FormerIdInSettingsApplies;
    [Test]
    procedure AliasesMapFormerIds;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Recursion,
  Atlas.Tests.RuleAssert;

const
  Header =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    function GetName: string;'#10 +
    '    procedure SetTitle(const AValue: string);'#10 +
    '  public'#10 +
    '    property Name: string read GetName;'#10 +
    '    property Title: string write SetTitle;'#10 +
    '  end;'#10 +
    'implementation'#10;

  // Beispiel aus #910: das Feld steht in read der Property.
  Kunde =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FKundenName: string;'#10 +
    '    procedure SetName(const Value: string);'#10 +
    '  public'#10 +
    '    property Name: string read FKundenName write SetName;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.SetName(const Value: string);'#10 +
    'begin'#10 +
    '  if Name <> Value then'#10 +
    '    Name := Value;'#10 +
    'end;'#10 +
    'end.';

  KundeFixed =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FKundenName: string;'#10 +
    '    procedure SetName(const Value: string);'#10 +
    '  public'#10 +
    '    property Name: string read FKundenName write SetName;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.SetName(const Value: string);'#10 +
    'begin'#10 +
    '  if FKundenName <> Value then'#10 +
    '    FKundenName := Value;'#10 +
    'end;'#10 +
    'end.';

{ TRecursionRulesTests }

procedure TRecursionRulesTests.SetterExampleIsErrorWithFieldFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde);
  // Das Lesen von Name ruft den Getter (hier ein Feld) nicht rekursiv auf, nur die Zuweisung.
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(SetterRecursionRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Zuweisung an die Property Name im eigenen Setter: Endlosrekursion.', Findings[0].Message);
  Assert.AreEqual(14, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Feld FKundenName verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Assert.AreEqual('FKundenName', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TRecursionRulesTests.GetterUsesFieldOfDeclaration;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := Name;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Lesen der Property Name im eigenen Getter: Endlosrekursion.', Findings[0].Message);
  Assert.AreEqual(15, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Character);
  // Ohne Feld in der Deklaration: F<Name> der Klasse.
  Assert.AreEqual('Feld FName verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual('FName', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TRecursionRulesTests.SetterWithoutFieldHasNoFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Header +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  Self.Title := AValue;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zuweisung an die Property Title im eigenen Setter: Endlosrekursion.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'kein Feld FTitle');
end;

procedure TRecursionRulesTests.FieldAccessIsSilent;
begin
  TRuleAssert.Silent(TSetterRecursionRule.Create, KundeFixed);
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;'#10 +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  FName := AValue + Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.OtherPropertyIsSilent;
begin
  // Ein Setter, der eine andere Property schreibt, ist keine Rekursion.
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  if Name = '''' then'#10 +
    '    FName := AValue;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.SuppressedByComment;
begin
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  // lsp-ignore: setter-recursion'#10 +
    '  Result := Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.FormerIdStillSuppresses;
begin
  TRuleAssert.Silent(TSetterRecursionRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  // lsp-ignore: recursive-property-accessor'#10 +
    '  Result := Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.OffAndExcludeSilence;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"setter-recursion": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"setter-recursion": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"setter-recursion": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Kunden.pas'))));
end;

procedure TRecursionRulesTests.FormerIdInSettingsApplies;
var
  Findings: TArray<TRuleFinding>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"recursive-property-accessor": "off"}}', 'Kunden.pas'))));
  Findings := TRuleAssert.Findings(TSetterRecursionRule.Create, Kunde,
    '{"rules": {"recursive-property-accessor": "warning"}}', 'Kunden.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TRecursionRulesTests.AliasesMapFormerIds;
begin
  Assert.AreEqual('setter-recursion', TRuleIdAliases.Current('recursive-property-accessor'));
  Assert.AreEqual('setter-recursion', TRuleIdAliases.Current('Recursive-Property-Accessor'));
  Assert.AreEqual('self-assignment', TRuleIdAliases.Current('self-assignment'));
end;

procedure TRecursionRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = SetterRecursionRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TRecursionRulesTests);

end.
