unit Atlas.Common.Rules.Builtin.Statements.Tests;

// Tests der Regel empty-statement (#912): Semikolon nach then, do und else mit
// Korrektur, leerer Block mit und ohne Kommentar (allowCommented), keine
// Meldung am Blockende, in case-else und bei richtigen Formen, Abschalten,
// Ausnahmen und falscher Optionstyp in atlas.json.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStatementRulesTests = class
  public
    [Test]
    procedure SemicolonAfterThenIsReportedWithFix;
    [Test]
    procedure SemicolonAfterDoAndElse;
    [Test]
    procedure EmptyBlockDependsOnComment;
    [Test]
    procedure CorrectFormsAreSilent;
    [Test]
    procedure NestedIfElseBelongsToInner;
    [Test]
    procedure OffAndExcludeSilence;
    [Test]
    procedure AllowCommentedMustBeBoolean;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Statements,
  Atlas.Tests.RuleAssert;

function Body(const AStatements: string): string;
begin
  Result := 'unit Daten;'#10'interface'#10'implementation'#10'procedure Laden(Liste: TList; Fertig: Boolean);'#10 +
    'var'#10'  I: Integer;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

{ TStatementRulesTests }

procedure TStatementRulesTests.SemicolonAfterThenIsReportedWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TEmptyStatementRule.Create,
    Body('  if Liste.Count = 0 then;'#10'    raise EKeineDaten.Create(''Keine Daten'');'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(EmptyStatementRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Leere Anweisung nach then: die nächste Zeile läuft immer.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(21, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Semikolon entfernen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Assert.AreEqual('', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(25, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(26, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
end;

procedure TStatementRulesTests.SemicolonAfterDoAndElse;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TEmptyStatementRule.Create,
    Body('  for I := 0 to Liste.Count - 1 do;'#10'    Liste.Delete(0);'#10 +
    '  while Liste.Count > 0 do;'#10'    Liste.Delete(0);'#10 +
    '  if Fertig then'#10'    Liste.Clear'#10'  else;'#10'    Liste.Pack;'#10));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Leere Anweisung nach do: die Schleife dreht leer.', Findings[0].Message);
  Assert.AreEqual('Leere Anweisung nach do: die Schleife dreht leer.', Findings[1].Message);
  Assert.AreEqual('Leere Anweisung nach else: die nächste Zeile läuft immer.', Findings[2].Message);
end;

procedure TStatementRulesTests.EmptyBlockDependsOnComment;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  Source := Body('  if Fertig then'#10'  begin'#10'  end;'#10 +
    '  if Liste = nil then'#10'  begin'#10'    { absichtlich leer }'#10'  end;'#10);
  Findings := TRuleAssert.Findings(TEmptyStatementRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Leerer Block nach then: hier passiert nichts.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Findings := TRuleAssert.Findings(TEmptyStatementRule.Create, Source,
    '{"rules": {"empty-statement": {"allowCommented": false}}}', 'Daten.pas');
  Assert.AreEqual(2, Integer(Length(Findings)), 'mit allowCommented = false auch der kommentierte Block');
end;

procedure TStatementRulesTests.CorrectFormsAreSilent;
begin
  TRuleAssert.Silent(TEmptyStatementRule.Create,
    Body('  if Liste.Count = 0 then'#10'    raise EKeineDaten.Create(''Keine Daten'');'#10 +
    '  if Fertig then'#10'    Liste.Clear;'#10 +
    '  case I of'#10'    1: Liste.Clear;'#10'  else;'#10'  end;'#10 +
    '  if Fertig then else'#10'    Liste.Clear;'#10 +
    '  for I := 0 to 3 do'#10'    if I = 2 then'#10'      Liste.Clear;'#10 +
    // Warteschleife am Blockende: das Semikolon ändert nichts.
    '  while Fertig do;'#10));
end;

procedure TStatementRulesTests.NestedIfElseBelongsToInner;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TEmptyStatementRule.Create,
    Body('  if Fertig then'#10'    if Liste = nil then'#10'      Liste.Clear'#10'    else;'#10 +
    '  Liste.Pack;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Leere Anweisung nach else: die nächste Zeile läuft immer.', Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
end;

procedure TStatementRulesTests.OffAndExcludeSilence;
const
  Source = '  if Fertig then;'#10'    Liste.Clear;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyStatementRule.Create, Body(Source),
    '{"rules": {"empty-statement": "off"}}', 'Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyStatementRule.Create, Body(Source),
    '{"rules": {"empty-statement": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Daten.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyStatementRule.Create, Body(Source),
    '{"rules": {"empty-statement": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Daten.pas'))));
end;

procedure TStatementRulesTests.AllowCommentedMustBeBoolean;
var
  Issues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse('{"rules": {"empty-statement": {"allowCommented": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowCommented" muss true oder false sein', Issues[0].Message);
  TConfigurationParser.Parse('{"rules": {"empty-statement": {"allowCommented": false}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TStatementRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = EmptyStatementRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TStatementRulesTests);

end.
