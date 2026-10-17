unit Atlas.Common.Rules.Builtin.Recursion.Tests;

// Tests der Regel recursive-property-accessor (#623): Getter und Setter der
// eigenen Property als Warnung, Feld als Korrektur, keine Meldung ohne Falle,
// Unterdrückung und Registrierung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRecursionRulesTests = class
  public
    [Test]
    procedure GetterIsWarningWithFieldFix;
    [Test]
    procedure SetterWithoutFieldHasNoFix;
    [Test]
    procedure FieldAccessIsSilent;
    [Test]
    procedure SuppressedByComment;
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

{ TRecursionRulesTests }

procedure TRecursionRulesTests.GetterIsWarningWithFieldFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TRecursivePropertyAccessorRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := Name;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(RecursivePropertyAccessorRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('Getter GetName liest die eigene Property Name und ruft sich damit endlos selbst auf; ' +
    'das Feld FName verwenden', Findings[0].Message);
  Assert.AreEqual(15, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Feld FName verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual('FName', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TRecursionRulesTests.SetterWithoutFieldHasNoFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TRecursivePropertyAccessorRule.Create, Header +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  Self.Title := AValue;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Setter SetTitle schreibt die eigene Property Title und ruft sich damit endlos selbst auf',
    Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'kein Feld FTitle');
end;

procedure TRecursionRulesTests.FieldAccessIsSilent;
begin
  TRuleAssert.Silent(TRecursivePropertyAccessorRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;'#10 +
    'procedure TFoo.SetTitle(const AValue: string);'#10'begin'#10'  FName := AValue + Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.SuppressedByComment;
begin
  TRuleAssert.Silent(TRecursivePropertyAccessorRule.Create, Header +
    'function TFoo.GetName: string;'#10'begin'#10'  // lsp-ignore: recursive-property-accessor'#10 +
    '  Result := Name;'#10'end;'#10'end.');
end;

procedure TRecursionRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = RecursivePropertyAccessorRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TRecursionRulesTests);

end.
