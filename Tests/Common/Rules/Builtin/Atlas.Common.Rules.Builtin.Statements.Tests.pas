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
    [Test]
    procedure CountUpperBoundIsReportedWithFix;
    [Test]
    procedure LengthOfArrayUsesHigh;
    [Test]
    procedure CorrectLoopsAreSilent;
    [Test]
    procedure StringLoopsAndZeroIndex;
    [Test]
    procedure ZeroBasedStringsDirective;
    [Test]
    procedure CountNamesOption;
    [Test]
    procedure LoopOffByOneOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
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

const
  ListHeader =
    'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class Name: string; end;'#10 +
    '  TKundenListe = class'#10'  private'#10'    FKunden: TList<TKunde>;'#10'    FZahlen: TArray<Integer>;'#10 +
    '    FText: string;'#10'    procedure Ausgeben;'#10'  end;'#10'implementation'#10;

function TokensOf(const AText: string): TArray<TPascalToken>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Tree.Tokens;
  finally
    Tree.Free;
  end;
end;

function ListBody(const AStatements: string): string;
begin
  Result := ListHeader + 'procedure TKundenListe.Ausgeben;'#10'var'#10'  I: Integer;'#10'  Kunden: TList<TKunde>;'#10 +
    'begin'#10'  Kunden := FKunden;'#10 + AStatements + 'end;'#10'end.';
end;

procedure TStatementRulesTests.CountUpperBoundIsReportedWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLoopOffByOneRule.Create,
    ListBody('  for I := 0 to Kunden.Count do'#10'    Ausgabe(Kunden[I].Name);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(LoopOffByOneRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Obergrenze Kunden.Count: der letzte Durchlauf greift hinter das Listenende (Index Count).',
    Findings[0].Message);
  Assert.AreEqual(18, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('„- 1“ ergänzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Assert.AreEqual(' - 1', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(28, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(28, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
  // Feld und Items[I] zählen mit.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLoopOffByOneRule.Create,
    ListBody('  for I := 0 to FKunden.Count do'#10'    FKunden.Items[I].Free;'#10)))));
end;

procedure TStatementRulesTests.LengthOfArrayUsesHigh;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLoopOffByOneRule.Create,
    ListBody('  for I := 0 to Length(FZahlen) do'#10'    FZahlen[I] := 0;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Obergrenze Length(FZahlen): der letzte Durchlauf greift hinter das Array-Ende (Index Length).',
    Findings[0].Message);
  Assert.AreEqual('High(FZahlen) verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual('High(FZahlen)', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TStatementRulesTests.CorrectLoopsAreSilent;
begin
  TRuleAssert.Silent(TLoopOffByOneRule.Create,
    ListBody('  for I := 0 to Kunden.Count - 1 do'#10'    Ausgabe(Kunden[I].Name);'#10 +
    '  for I := 0 to High(FZahlen) do'#10'    FZahlen[I] := 0;'#10 +
    // Ohne Zugriff Kunden[I]: 0 bis Count kann gewollt sein (Count + 1 Durchläufe).
    '  for I := 0 to Kunden.Count do'#10'    Ausgabe(IntToStr(I));'#10 +
    // Anderes Objekt im Rumpf.
    '  for I := 0 to Kunden.Count do'#10'    Ausgabe(Self.Kunden[I].Name);'#10 +
    '  for I := 1 to Kunden.Count do'#10'    Ausgabe(Kunden[I - 1].Name);'#10 +
    '  for I := Kunden.Count downto 0 do'#10'    Ausgabe(Kunden[I].Name);'#10 +
    '  for I := 1 to Length(FText) do'#10'    Ausgabe(FText[I]);'#10));
end;

procedure TStatementRulesTests.StringLoopsAndZeroIndex;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLoopOffByOneRule.Create,
    ListBody('  for I := 0 to Length(FText) do'#10'    Ausgabe(FText[I]);'#10 +
    '  for I := 0 to Length(FText) - 1 do'#10'    Ausgabe(FText[I]);'#10 +
    '  if FText[0] = ''#'' then'#10'    Exit;'#10));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Strings beginnen bei 1: der erste Durchlauf greift auf FText[0].', Findings[0].Message);
  Assert.AreEqual('Low(FText)/High(FText) verwenden', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Low(FText) to High(FText)', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('Strings beginnen bei 1: der erste Durchlauf greift auf FText[0].', Findings[1].Message);
  Assert.AreEqual('Low(FText) to High(FText)', Findings[1].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('Strings beginnen bei 1: FText[0] liegt vor dem ersten Zeichen.', Findings[2].Message);
  Assert.AreEqual('Low(FText)', Findings[2].Fixes[0].Edits[0].NewText);
end;

procedure TStatementRulesTests.ZeroBasedStringsDirective;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLoopOffByOneRule.Create, '{$ZEROBASEDSTRINGS ON}'#10 +
    ListBody('  for I := 0 to Length(FText) do'#10'    Ausgabe(FText[I]);'#10 +
    '  for I := 1 to Length(FText) do'#10'    Ausgabe(FText[I]);'#10 +
    '  for I := 0 to Length(FText) - 1 do'#10'    Ausgabe(FText[I]);'#10 +
    '  if FText[0] = ''#'' then'#10'    Exit;'#10));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Obergrenze Length(FText): der letzte Durchlauf greift hinter das String-Ende ' +
    '(mit {$ZEROBASEDSTRINGS ON} sind Strings nullbasiert).', Findings[0].Message);
  Assert.AreEqual('Mit {$ZEROBASEDSTRINGS ON} sind Strings nullbasiert: die Schleife überspringt FText[0] ' +
    'und greift hinter das Ende.', Findings[1].Message);
  Assert.IsTrue(TLoopOffByOneRule.ZeroBasedStrings(TokensOf('{$ZEROBASEDSTRINGS+} unit U;')));
  Assert.IsFalse(TLoopOffByOneRule.ZeroBasedStrings(TokensOf(
    '{$ZEROBASEDSTRINGS ON}{$ZEROBASEDSTRINGS OFF} unit U;')));
end;

procedure TStatementRulesTests.CountNamesOption;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLoopOffByOneRule.Create,
    ListBody('  for I := 0 to Kunden.Anzahl do'#10'    Ausgabe(Kunden[I].Name);'#10),
    '{"rules": {"loop-off-by-one": {"countNames": ["Anzahl"]}}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLoopOffByOneRule.Create,
    ListBody('  for I := 0 to Kunden.Count do'#10'    Ausgabe(Kunden[I].Name);'#10),
    '{"rules": {"loop-off-by-one": {"countNames": ["Anzahl"]}}}', 'Kunden.pas'))));
  TConfigurationParser.Parse('{"rules": {"loop-off-by-one": {"countNames": "Count"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"countNames" muss eine Liste von Texten sein', Issues[0].Message);
end;

procedure TStatementRulesTests.LoopOffByOneOffAndExclude;
const
  Source = '  for I := 0 to Kunden.Count do'#10'    Ausgabe(Kunden[I].Name);'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLoopOffByOneRule.Create, ListBody(Source),
    '{"rules": {"loop-off-by-one": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLoopOffByOneRule.Create, ListBody(Source),
    '{"rules": {"loop-off-by-one": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLoopOffByOneRule.Create, ListBody(Source),
    '{"rules": {"loop-off-by-one": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Kunden.pas'))));
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
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = LoopOffByOneRuleId then
      Found := True;
  Assert.IsTrue(Found, LoopOffByOneRuleId);
end;

initialization
  TDUnitX.RegisterTestFixture(TStatementRulesTests);

end.
