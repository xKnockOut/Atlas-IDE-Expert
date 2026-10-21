unit Atlas.Common.Rules.Builtin.Expressions.Tests;

// Tests der Regel operator-precedence (#911): not vor in und Vergleichen bei
// Aufzählungen und Ganzzahlen, Klammern als Korrektur, keine Meldung bei
// Boolean, unbekanntem Typ und geklammerter Form, Abschalten und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExpressionRulesTests = class
  public
    [Test]
    procedure NotBeforeInIsReportedWithFix;
    [Test]
    procedure NotOnIntegerComparisonIsBitwise;
    [Test]
    procedure NotOnEnumComparison;
    [Test]
    procedure ParenthesizedFormIsSilent;
    [Test]
    procedure BooleanAndUnknownTypesAreSilent;
    [Test]
    procedure RightOperandEndsAtAnd;
    [Test]
    procedure OffAndExcludeSilence;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Expressions,
  Atlas.Tests.RuleAssert;

const
  Header =
    'unit Ablauf;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TZustand = (zsNeu, zsOffen, zsGesperrt);'#10 +
    '  TVorgang = class'#10 +
    '  private'#10 +
    '    FZustand: TZustand;'#10 +
    '    FAnzahl: Integer;'#10 +
    '    FFertig: Boolean;'#10 +
    '    procedure Bearbeiten;'#10 +
    '    procedure Pruefen(AWert: Variant);'#10 +
    '  end;'#10 +
    'implementation'#10;

function Body(const AStatements: string): string;
begin
  Result := Header + 'procedure TVorgang.Pruefen(AWert: Variant);'#10'var'#10'  Zustand: TZustand;'#10 +
    'begin'#10'  Zustand := FZustand;'#10 + AStatements + 'end;'#10'procedure TVorgang.Bearbeiten;'#10 +
    'begin'#10'end;'#10'end.';
end;

{ TExpressionRulesTests }

procedure TExpressionRulesTests.NotBeforeInIsReportedWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOperatorPrecedenceRule.Create,
    Body('  if not Zustand in [zsOffen, zsGesperrt] then'#10'    Bearbeiten;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(OperatorPrecedenceRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('„not“ gilt nur für Zustand, nicht für den in-Ausdruck. ' +
    'Gemeint ist vermutlich not (Zustand in […]).', Findings[0].Message);
  Assert.AreEqual(18, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Klammern setzen: not (Zustand in […])', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Assert.AreEqual('(Zustand in [zsOffen, zsGesperrt])', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(9, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(41, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
end;

procedure TExpressionRulesTests.NotOnIntegerComparisonIsBitwise;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOperatorPrecedenceRule.Create,
    Body('  if not FAnzahl = 0 then'#10'    Bearbeiten;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('„not“ kehrt die Ganzzahl FAnzahl bitweise um, nicht den Vergleich. ' +
    'Gemeint ist vermutlich not (FAnzahl = 0).', Findings[0].Message);
  Assert.AreEqual('(FAnzahl = 0)', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TExpressionRulesTests.NotOnEnumComparison;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOperatorPrecedenceRule.Create,
    Body('  while not FZustand <> zsNeu do'#10'    Bearbeiten;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('„not“ gilt nur für FZustand, nicht für den Vergleich. ' +
    'Gemeint ist vermutlich not (FZustand <> zsNeu).', Findings[0].Message);
end;

procedure TExpressionRulesTests.ParenthesizedFormIsSilent;
begin
  TRuleAssert.Silent(TOperatorPrecedenceRule.Create,
    Body('  if not (Zustand in [zsOffen, zsGesperrt]) then'#10'    Bearbeiten;'#10 +
    '  if not (FAnzahl = 0) then'#10'    Bearbeiten;'#10));
end;

procedure TExpressionRulesTests.BooleanAndUnknownTypesAreSilent;
begin
  // not auf Boolean ist gemeint; Variant und Unbekanntes lassen sich nicht sicher beurteilen.
  TRuleAssert.Silent(TOperatorPrecedenceRule.Create,
    Body('  if not FFertig = True then'#10'    Bearbeiten;'#10 +
    '  if not AWert = 1 then'#10'    Bearbeiten;'#10 +
    '  if not Unbekannt in [1, 2] then'#10'    Bearbeiten;'#10 +
    '  if not Assigned(Self) = False then'#10'    Bearbeiten;'#10));
end;

procedure TExpressionRulesTests.RightOperandEndsAtAnd;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOperatorPrecedenceRule.Create,
    Body('  if not FAnzahl > 10 and FFertig then'#10'    Bearbeiten;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('(FAnzahl > 10)', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TExpressionRulesTests.OffAndExcludeSilence;
const
  Source = '  if not Zustand in [zsOffen] then'#10'    Bearbeiten;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOperatorPrecedenceRule.Create, Body(Source),
    '{"rules": {"operator-precedence": "off"}}', 'Ablauf.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOperatorPrecedenceRule.Create, Body(Source),
    '{"rules": {"operator-precedence": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Ablauf.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOperatorPrecedenceRule.Create, Body(Source),
    '{"rules": {"operator-precedence": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Ablauf.pas'))));
end;

procedure TExpressionRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = OperatorPrecedenceRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionRulesTests);

end.
