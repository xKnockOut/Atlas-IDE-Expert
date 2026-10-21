unit Atlas.Common.Rules.Builtin.FreeFields.Tests;

// Tests für owned-field-not-freed und owned-field-free-unclear (#666).

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
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
  Assert.AreEqual('"FList" wird in TFoo.Create erzeugt, aber in TFoo nirgends freigegeben', Findings[0].Message);
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

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldRulesTests);

end.
