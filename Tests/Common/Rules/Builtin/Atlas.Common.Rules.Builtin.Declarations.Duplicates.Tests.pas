unit Atlas.Common.Rules.Builtin.Declarations.Duplicates.Tests;

// Tests der Teilunit duplicate-declaration: lokale Variable mit dem Namen eines Parameters, doppelter Wert einer
// Aufzählung (#1345).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationDuplicatesTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
    [Test]
    procedure DuplicateEnumValue;
    [Test]
    procedure EnumValuesInExpressionsAreSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.Duplicates,
  Atlas.Tests.RuleAssert;

procedure TDeclarationDuplicatesTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Summieren(Betrag: Currency);'#10'var'#10'  Betrag: Currency;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('duplicate-declaration', mFindings[0].RuleId);
end;

procedure TDeclarationDuplicatesTests.IsSilent;
begin
  TRuleAssert.Silent(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Summieren(Betrag: Currency);'#10'var'#10'  Summe: Currency;'#10'begin'#10'end;'#10'end.');
end;

procedure TDeclarationDuplicatesTests.DuplicateEnumValue;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TTextId = (Start, { Suche } SettingsOverviewSearch,'#10'    Ende, SettingsOverviewSearch);'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual('SettingsOverviewSearch ist schon als Wert der Aufzählung deklariert (wie E2004).',
    mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TDeclarationDuplicatesTests.EnumValuesInExpressionsAreSilent;
begin
  // Werte mit Ausdruck aus einem früheren Wert und gleiche Namen in zwei Aufzählungen.
  TRuleAssert.Silent(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TFarbe = (Rot, Gruen = Rot + 2, Blau = Ord(Rot) + Ord(Gruen));'#10 +
    '  {$SCOPEDENUMS ON}'#10'  TArt = (Rot, Blau);'#10'implementation'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationDuplicatesTests);

end.
