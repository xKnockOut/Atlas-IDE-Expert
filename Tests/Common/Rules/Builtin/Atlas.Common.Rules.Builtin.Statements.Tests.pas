unit Atlas.Common.Rules.Builtin.Statements.Tests;

// Tests der Regel empty-statement (#912): Semikolon nach then, do und else mit
// Korrektur, leerer Block mit und ohne Kommentar (allowCommented), keine
// Meldung am Blockende, in case-else und bei richtigen Formen, Abschalten,
// Ausnahmen und falscher Optionstyp in atlas.json. Danach loop-off-by-one
// (#913) und collection-modified-in-loop (#914): Beispiel mit Korrektur nach
// downto, for … in, Add und Insert, Break/Exit und downto still, Option
// mutatingMethods, Abschalten und Ausnahmen. Zuletzt destroy-called-directly
// (#920): Beispiel mit Korrektur, inherited Destroy, Destroy mit Argumenten,
// Abschalten und Ausnahmen. case-missing-enum-value (#929): Beispiel mit
// Korrektur, Feld über eine Kette, Aufzählung mit Typpräfix, else mit und ohne
// requireElse, Bereiche und vollständige case-Anweisungen.
// comparison-as-statement (#982): Beispiel mit Korrektur, Feld, Element,
// Zeiger, nach then und in Klammern, ohne Korrektur bei Aufruf links und
// anderen Ausdrücken, stille Fälle, Abschalten, Gruppe und Ausnahmen.
// duplicate-case-label (#983): Beispiel mit Korrektur (Zweig bzw. ein Wert),
// Bereiche, Konstanten, Zeichen, Aufzählungsbereiche, varianter Record, stille
// Fälle (unbekannte Namen, Aufzählung mit eigenen Werten), Abschalten.

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
    [Test]
    procedure DeleteInForwardLoopIsReportedWithFix;
    [Test]
    procedure ForInAddAndInsertMessages;
    [Test]
    procedure SafeModificationsAreSilent;
    [Test]
    procedure MutatingMethodsOption;
    [Test]
    procedure CollectionModifiedOffAndExclude;
    [Test]
    procedure DestroyCalledDirectlyIssueExample;
    [Test]
    procedure DestroyCalledDirectlySilentCases;
    [Test]
    procedure DestroyCalledDirectlyOffAndExclude;
    [Test]
    procedure CaseMissingEnumValueIssueExample;
    [Test]
    procedure CaseMissingEnumValueVariants;
    [Test]
    procedure CaseMissingEnumValueSilentCases;
    [Test]
    procedure CaseMissingEnumValueOptions;
    [Test]
    procedure DatasetLoopIssueExample;
    [Test]
    procedure DatasetLoopVariants;
    [Test]
    procedure DatasetLoopSilentCases;
    [Test]
    procedure DatasetLoopOffAndExclude;
    [Test]
    procedure DatasetEditIssueExample;
    [Test]
    procedure DatasetEditVariants;
    [Test]
    procedure DatasetEditSilentCases;
    [Test]
    procedure DatasetEditOffAndExclude;
    [Test]
    procedure TransactionIssueExample;
    [Test]
    procedure TransactionVariants;
    [Test]
    procedure TransactionSilentCases;
    [Test]
    procedure TransactionOptions;
    [Test]
    procedure ComparisonAsStatementIssueExample;
    [Test]
    procedure ComparisonAsStatementVariants;
    [Test]
    procedure ComparisonAsStatementSilentCases;
    [Test]
    procedure ComparisonAsStatementOffAndExclude;
    [Test]
    procedure DuplicateCaseLabelIssueExample;
    [Test]
    procedure DuplicateCaseLabelValues;
    [Test]
    procedure DuplicateCaseLabelVariantRecord;
    [Test]
    procedure DuplicateCaseLabelFromIndex;
    [Test]
    procedure DuplicateCaseLabelSilentCases;
    [Test]
    procedure DuplicateCaseLabelOffAndExclude;
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
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.ChangeSignature,
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

procedure TStatementRulesTests.DeleteInForwardLoopIsReportedWithFix;
const
  Loop = '  for I := 0 to Kunden.Count - 1 do'#10'    if Kunden[I].Name = '''' then'#10'      Kunden.Delete(I);'#10;
  Fixed = '  for I := Kunden.Count - 1 downto 0 do'#10'    if Kunden[I].Name = '''' then'#10'      Kunden.Delete(I);'#10;
var
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create, ListBody(Loop));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(CollectionModifiedInLoopRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Kunden.Delete in einer Vorwärtsschleife über Kunden: das nächste Element wird übersprungen, ' +
    'am Ende folgt ein Indexfehler.', Findings[0].Message);
  Assert.AreEqual(20, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Schleife rückwärts (downto) umschreiben', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Text := TChangeSignature.ApplyEdits(ListBody(Loop), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(ListBody(Fixed), Text);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TCollectionModifiedInLoopRule.Create, ListBody(Fixed));
  // High, Pred und Length(A) - 1 als Obergrenze ebenso.
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create,
    ListBody('  for I := 0 to Pred(FKunden.Count) do'#10'    FKunden.Remove(nil);'#10 +
    '  for I := 0 to High(FZahlen) do'#10'    FZahlen.Delete(I);'#10)))));
end;

procedure TStatementRulesTests.ForInAddAndInsertMessages;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create,
    ListBody('  for var Kunde in Kunden do'#10'    if Kunde.Name = '''' then'#10'      Kunden.Remove(Kunde);'#10 +
    '  for var Kunde in FKunden do'#10'    FKunden.Clear;'#10 +
    '  for I := 0 to Kunden.Count - 1 do'#10'    Kunden.Add(Kunden[I]);'#10 +
    '  for I := 0 to Kunden.Count - 1 do'#10'    Kunden.Insert(0, Kunden[I]);'#10));
  Assert.AreEqual(4, Integer(Length(Findings)));
  Assert.AreEqual('Kunden.Remove in for … in über Kunden: die RTL wirft eine Exception, weil sich die Liste ' +
    'ändert. Elemente sammeln und nach der Schleife ändern.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'for … in: nur Hinweis');
  Assert.AreEqual('FKunden.Clear in for … in über FKunden: die RTL wirft eine Exception, weil sich die Liste ' +
    'ändert. Elemente sammeln und nach der Schleife ändern.', Findings[1].Message);
  Assert.AreEqual('Kunden.Add in einer Vorwärtsschleife über Kunden: die neuen Elemente durchläuft die Schleife ' +
    'nicht, die Obergrenze steht beim Start fest.', Findings[2].Message);
  Assert.AreEqual(0, Integer(Length(Findings[2].Fixes)), 'downto hilft bei Add nicht');
  Assert.AreEqual('Kunden.Insert in einer Vorwärtsschleife über Kunden: die Elemente rücken nach, dasselbe ' +
    'Element kommt noch einmal, am Ende fehlen Elemente.', Findings[3].Message);
end;

procedure TStatementRulesTests.SafeModificationsAreSilent;
begin
  TRuleAssert.Silent(TCollectionModifiedInLoopRule.Create,
    // Rückwärts ist Löschen unbedenklich.
    ListBody('  for I := Kunden.Count - 1 downto 0 do'#10'    Kunden.Delete(I);'#10 +
    // Break oder Exit direkt danach beenden die Schleife.
    '  for I := 0 to Kunden.Count - 1 do'#10'    if Kunden[I].Name = '''' then'#10'    begin'#10 +
    '      Kunden.Delete(I);'#10'      Break;'#10'    end;'#10 +
    '  for var Kunde in Kunden do'#10'    if Kunde.Name = '''' then'#10'    begin'#10 +
    '      Kunden.Remove(Kunde);'#10'      Exit;'#10'    end;'#10 +
    // Andere Liste, Methode einer anderen Liste, Lesen.
    '  for I := 0 to Kunden.Count - 1 do'#10'    FKunden.Delete(0);'#10 +
    '  for I := 0 to Kunden.Count - 1 do'#10'    Kunden[I].Liste.Delete(0);'#10 +
    '  for var Kunde in Kunden do'#10'    Ausgabe(Kunden.IndexOf(Kunde));'#10 +
    // Feste Obergrenze: keine Schleife über die Liste.
    '  for I := 0 to 9 do'#10'    Kunden.Delete(0);'#10));
end;

procedure TStatementRulesTests.MutatingMethodsOption;
const
  Source = '  for I := 0 to Kunden.Count - 1 do'#10'    Kunden.Loeschen(I);'#10 +
    '  for I := 0 to Kunden.Count - 1 do'#10'    Kunden.Delete(I);'#10;
var
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Findings := TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create, ListBody(Source));
  Assert.AreEqual(1, Integer(Length(Findings)), 'Vorgabe: nur Delete');
  Assert.AreEqual(21, Findings[0].Range.StartPos.Line);
  Findings := TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create, ListBody(Source),
    '{"rules": {"collection-modified-in-loop": {"mutatingMethods": ["Loeschen"]}}}', 'Kunden.pas');
  Assert.AreEqual(1, Integer(Length(Findings)), 'Option: nur Loeschen');
  Assert.AreEqual(19, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(6, Integer(Length(TCollectionModifiedInLoopRule.DefaultMutatingMethods)));
  TConfigurationParser.Parse('{"rules": {"collection-modified-in-loop": {"mutatingMethods": "Delete"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"mutatingMethods" muss eine Liste von Texten sein', Issues[0].Message);
end;

procedure TStatementRulesTests.CollectionModifiedOffAndExclude;
const
  Source = '  for I := 0 to Kunden.Count - 1 do'#10'    Kunden.Delete(I);'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create, ListBody(Source),
    '{"rules": {"collection-modified-in-loop": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create, ListBody(Source),
    '{"rules": {"collection-modified-in-loop": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCollectionModifiedInLoopRule.Create, ListBody(Source),
    '{"rules": {"collection-modified-in-loop": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Kunden.pas'))));
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
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = CollectionModifiedInLoopRuleId then
      Found := True;
  Assert.IsTrue(Found, CollectionModifiedInLoopRuleId);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = DestroyCalledDirectlyRuleId then
      Found := True;
  Assert.IsTrue(Found, DestroyCalledDirectlyRuleId);
end;

procedure TStatementRulesTests.DestroyCalledDirectlyIssueExample;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TDestroyCalledDirectlyRule.Create, Body('  Verbindung.Destroy;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Destroy direkt aufgerufen; Free prüft vorher auf nil.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(13, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('Free statt Destroy', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Text := TChangeSignature.ApplyEdits(Body('  Verbindung.Destroy;'#10), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Body('  Verbindung.Free;'#10), Text);
  TRuleAssert.Silent(TDestroyCalledDirectlyRule.Create, Text);
  // Mit Klammern und über eine Typumwandlung ebenso.
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TDestroyCalledDirectlyRule.Create,
    Body('  Liste.Destroy();'#10'  TObject(Liste).Destroy;'#10)))));
end;

procedure TStatementRulesTests.DestroyCalledDirectlySilentCases;
begin
  // inherited Destroy im Destruktor, eigener Destruktor mit Argumenten, Methodenzeiger.
  TRuleAssert.Silent(TDestroyCalledDirectlyRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'destructor TFoo.Destroy;'#10'begin'#10'  FListe.Free;'#10'  inherited Destroy;'#10'end;'#10'end.');
  TRuleAssert.Silent(TDestroyCalledDirectlyRule.Create, Body('  Knoten.Destroy(True);'#10 +
    '  Ereignis := Liste.Destroy;'#10));
end;

procedure TStatementRulesTests.DestroyCalledDirectlyOffAndExclude;
const
  Source = '  Verbindung.Destroy;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDestroyCalledDirectlyRule.Create, Body(Source),
    '{"rules": {"destroy-called-directly": "off"}}', 'Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDestroyCalledDirectlyRule.Create, Body(Source),
    '{"rules": {"destroy-called-directly": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Daten.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDestroyCalledDirectlyRule.Create, Body(Source),
    '{"rules": {"destroy-called-directly": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Daten.pas'))));
end;

function Bestellung(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 +
    '  TBestellStatus = (bsNeu, bsBezahlt, bsStorniert, bsZurueck);'#10 +
    '  TBestellung = class'#10'    Status: TBestellStatus;'#10'  end;'#10'implementation'#10 +
    'procedure Bearbeiten(Bestellung: TBestellung; Stand: TBestellStatus);'#10'begin'#10 + ABody + #10 +
    'end;'#10'end.';
end;

procedure TStatementRulesTests.CaseMissingEnumValueIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Bestellung('  case Bestellung.Status of'#10'    bsNeu: Anlegen;'#10'    bsBezahlt: Versenden;'#10 +
    '  end;');
  Findings := TRuleAssert.Findings(TCaseMissingEnumValueRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Fehlende Werte von TBestellStatus: bsStorniert, bsZurueck.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Fehlende Werte ergänzen (2)', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Bestellung('  case Bestellung.Status of'#10'    bsNeu: Anlegen;'#10'    bsBezahlt: Versenden;'#10 +
    '    bsStorniert: ;'#10'    bsZurueck: ;'#10'  end;'), Fixed);
  TRuleAssert.Silent(TCaseMissingEnumValueRule.Create, Fixed);
end;

procedure TStatementRulesTests.CaseMissingEnumValueVariants;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  // Parameter, Bereich und Liste zählen als vorhanden.
  Findings := TRuleAssert.Findings(TCaseMissingEnumValueRule.Create, Bestellung('  case Stand of'#10 +
    '    bsNeu..bsBezahlt: Anlegen;'#10'  end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Fehlende Werte von TBestellStatus: bsStorniert, bsZurueck.', Findings[0].Message);
  // {$SCOPEDENUMS ON}: neue Zweige mit Typpräfix.
  Source := 'unit U;'#10'interface'#10'type'#10'  TAmpel = (Rot, Gelb, Gruen);'#10'implementation'#10 +
    'procedure Schalten(A: TAmpel);'#10'begin'#10'  case A of'#10'    TAmpel.Rot: Halten;'#10'  end;'#10'end;'#10 +
    'end.';
  Findings := TRuleAssert.Findings(TCaseMissingEnumValueRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Pos('TAmpel.Gelb: ;', TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits)) > 0);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCaseMissingEnumValueRule.Create,
    Bestellung('  case Stand of'#10'    bsNeu: ;'#10'  end;'), '{"rules": {"case-missing-enum-value": "off"}}',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCaseMissingEnumValueRule.Create,
    Bestellung('  case Stand of'#10'    bsNeu: ;'#10'  end;'),
    '{"rules": {"case-missing-enum-value": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
end;

procedure TStatementRulesTests.CaseMissingEnumValueSilentCases;
begin
  // Vollständig, mit else, Ganzzahl, unbekannter Typ, Aufruf als Selektor.
  TRuleAssert.Silent(TCaseMissingEnumValueRule.Create, Bestellung('  case Stand of'#10 +
    '    bsNeu, bsBezahlt: Anlegen;'#10'    bsStorniert..bsZurueck: ;'#10'  end;'#10'  case Stand of'#10 +
    '    bsNeu: Anlegen;'#10'  else'#10'    Protokoll;'#10'  end;'#10'  case Bestellung.Tag of'#10 +
    '    1: Anlegen;'#10'  end;'#10'  case Fremd of'#10'    fxA: ;'#10'  end;'#10'  case Lesen(Stand) of'#10 +
    '    bsNeu: ;'#10'  end;'));
end;

procedure TStatementRulesTests.CaseMissingEnumValueOptions;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Bestellung('  case Stand of'#10'    bsNeu: Anlegen;'#10'  else'#10'    Protokoll;'#10'  end;');
  Findings := TRuleAssert.Findings(TCaseMissingEnumValueRule.Create, Source,
    '{"rules": {"case-missing-enum-value": {"requireElse": true}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Fehlende Werte von TBestellStatus: bsBezahlt, bsStorniert, bsZurueck.', Findings[0].Message);
  Assert.IsTrue(Pos('bsZurueck: ;'#10'  else', TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits)) > 0);
  TConfigurationParser.Parse('{"rules": {"case-missing-enum-value": {"requireElse": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"requireElse" muss true oder false sein', Issues[0].Message);
end;

procedure TStatementRulesTests.DatasetLoopIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Body('  qryPositionen.First;'#10'  while not qryPositionen.Eof do'#10'  begin'#10 +
    '    Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;'#10'  end;'#10);
  Findings := TRuleAssert.Findings(TDatasetLoopWithoutNextRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('dataset-loop-without-next', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Im Rumpf fehlt qryPositionen.Next; die Schleife läuft endlos.', Findings[0].Message);
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(8, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('qryPositionen.Next; am Ende des Rumpfs einfügen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Body('  qryPositionen.First;'#10'  while not qryPositionen.Eof do'#10'  begin'#10 +
    '    Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;'#10'    qryPositionen.Next;'#10 +
    '  end;'#10), Fixed);
  TRuleAssert.Silent(TDatasetLoopWithoutNextRule.Create, Fixed);
end;

procedure TStatementRulesTests.DatasetLoopVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Next nur in einem Zweig bzw. vor Continue übersprungen: mittlere Konfidenz, keine Korrektur.
  Findings := TRuleAssert.Findings(TDatasetLoopWithoutNextRule.Create, Body('  while not Q.Eof do'#10'  begin'#10 +
    '    if Q.FieldByName(''Aktiv'').AsBoolean then'#10'      Q.Next;'#10'  end;'#10'  while not Self.Daten.Eof do'#10 +
    '  begin'#10'    if Fertig then'#10'      Continue;'#10'    Self.Daten.Next;'#10'  end;'#10 +
    '  while not Q.Eof do'#10'    Summe := Summe + 1;'#10));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Nicht jeder Weg durch den Rumpf ruft Q.Next auf; dort läuft die Schleife endlos.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Nicht jeder Weg durch den Rumpf ruft Self.Daten.Next auf; dort läuft die Schleife endlos.',
    Findings[1].Message);
  // Einzelne Anweisung ohne begin: gemeldet, ohne Korrektur.
  Assert.AreEqual('Im Rumpf fehlt Q.Next; die Schleife läuft endlos.', Findings[2].Message);
  Assert.AreEqual(0, Integer(Length(Findings[2].Fixes)));
end;

procedure TStatementRulesTests.DatasetLoopSilentCases;
begin
  // Next in allen Zweigen, Delete, Break/Exit/raise, try … finally, Datenmenge weitergegeben, with, andere Bedingung.
  TRuleAssert.Silent(TDatasetLoopWithoutNextRule.Create, Body('  while not Q.Eof do'#10'  begin'#10 +
    '    if Fertig then'#10'      Q.Delete'#10'    else'#10'      Q.Next;'#10'  end;'#10 +
    '  while not Q.Eof do'#10'  begin'#10'    if Fertig then'#10'      Break;'#10'    Q.Next;'#10'  end;'#10 +
    '  while not Q.Eof do'#10'  begin'#10'    try'#10'      Lesen;'#10'    finally'#10'      Q.Next;'#10 +
    '    end;'#10'  end;'#10'  while not Q.Eof do'#10'    Verarbeiten(Q);'#10 +
    '  while not Q.Eof do'#10'    with Q do'#10'      Next;'#10'  while not Fertig do'#10'    Lesen;'#10 +
    '  while not Q.Eof do'#10'    raise EAbbruch.Create(''x'');'#10));
end;

procedure TStatementRulesTests.DatasetLoopOffAndExclude;
var
  Source: string;
begin
  Source := Body('  while not Q.Eof do'#10'    Lesen;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDatasetLoopWithoutNextRule.Create, Source,
    '{"rules": {"dataset-loop-without-next": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDatasetLoopWithoutNextRule.Create, Source,
    '{"rules": {"dataset-loop-without-next": {"exclude": ["Source/*.pas"]}}}', 'Source/Daten.pas'))));
end;

procedure TStatementRulesTests.DatasetEditIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := Body('  tblKunde.Edit;'#10'  tblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);'#10 +
    '  Protokollieren;'#10);
  Findings := TRuleAssert.Findings(TDatasetEditWithoutPostRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('dataset-edit-without-post', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('Nach Edit fehlt Post oder Cancel; die Änderung bleibt offen.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(15, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('tblKunde.Post mit try … except Cancel ergänzen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Body('  tblKunde.Edit;'#10'  try'#10'    tblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);'#10 +
    '    tblKunde.Post;'#10'  except'#10'    tblKunde.Cancel;'#10'    raise;'#10'  end;'#10'  Protokollieren;'#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TDatasetEditWithoutPostRule.Create, Fixed);
end;

procedure TStatementRulesTests.DatasetEditVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Append und Insert(); ohne folgende Zuweisung keine Korrektur; Post vor dem Edit zählt nicht.
  Findings := TRuleAssert.Findings(TDatasetEditWithoutPostRule.Create, Body('  Q.Post;'#10'  Q.Append;'#10 +
    '  Q[''Name''] := Name;'#10'  Q.FieldValues[''Ort''] := Ort;'#10'  R.Insert();'#10'  Weiter;'#10));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Nach Append fehlt Post oder Cancel; die Änderung bleibt offen.', Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
end;

procedure TStatementRulesTests.DatasetEditSilentCases;
begin
  // Post, Cancel, CheckBrowseMode, Post in anderer Routine, weitergegeben, Insert mit Argumenten, Edit ohne Empfänger.
  TRuleAssert.Silent(TDatasetEditWithoutPostRule.Create, Body('  A.Edit;'#10'  A[''X''] := 1;'#10'  A.Post;'#10 +
    '  B.Append;'#10'  if Fehler then B.Cancel;'#10'  C.Insert;'#10'  C.CheckBrowseMode;'#10'  D.Edit;'#10 +
    '  Speichern(D);'#10'  Liste.Insert(0, ''x'');'#10'  Edit;'#10));
  TRuleAssert.Silent(TDatasetEditWithoutPostRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TForm1.BearbeitenClick(Sender: TObject);'#10'begin'#10'  tblKunde.Edit;'#10'end;'#10 +
    'procedure TForm1.SpeichernClick(Sender: TObject);'#10'begin'#10'  tblKunde.Post;'#10'end;'#10'end.');
end;

procedure TStatementRulesTests.DatasetEditOffAndExclude;
var
  Source: string;
begin
  Source := Body('  Q.Edit;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDatasetEditWithoutPostRule.Create, Source,
    '{"rules": {"dataset-edit-without-post": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDatasetEditWithoutPostRule.Create, Source,
    '{"rules": {"dataset-edit-without-post": {"exclude": ["Source/*.pas"]}}}', 'Source/Daten.pas'))));
end;

procedure TStatementRulesTests.TransactionIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Body('  Verbindung.StartTransaction;'#10'  Buchen(Auftrag);'#10'  Verbindung.Commit;'#10);
  Findings := TRuleAssert.Findings(TTransactionWithoutRollbackRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('transaction-without-rollback', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Kein Rollback bei einer Exception; die Transaktion bleibt offen und hält Sperren.',
    Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(13, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(29, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('try … except Verbindung.Rollback; raise; end erzeugen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Body('  Verbindung.StartTransaction;'#10'  try'#10'    Buchen(Auftrag);'#10'    Verbindung.Commit;'#10 +
    '  except'#10'    Verbindung.Rollback;'#10'    raise;'#10'  end;'#10), Fixed);
  TRuleAssert.Silent(TTransactionWithoutRollbackRule.Create, Fixed);
end;

procedure TStatementRulesTests.TransactionVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // ADO, dbExpress mit Transaktionsobjekt, ohne Commit (keine Korrektur), Rollback auf anderer Verbindung.
  Source := Body('  ADO.BeginTrans;'#10'  Buchen;'#10'  ADO.CommitTrans;'#10'  T := Sql.BeginTransaction;'#10 +
    '  Buchen;'#10'  Sql.CommitFreeAndNil(T);'#10'  A.StartTransaction;'#10'  Buchen;'#10 +
    '  B.StartTransaction;'#10'  try'#10'    Buchen;'#10'    B.Commit;'#10'  except'#10'    A.Rollback;'#10 +
    '    raise;'#10'  end;'#10);
  Findings := TRuleAssert.Findings(TTransactionWithoutRollbackRule.Create, Source);
  Assert.AreEqual(4, Integer(Length(Findings)));
  Assert.AreEqual('try … except ADO.RollbackTrans; raise; end erzeugen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(Body('  ADO.BeginTrans;'#10'  Buchen;'#10'  ADO.CommitTrans;'#10'  T := Sql.BeginTransaction;'#10 +
    '  try'#10'    Buchen;'#10'    Sql.CommitFreeAndNil(T);'#10'  except'#10'    Sql.RollbackFreeAndNil(T);'#10 +
    '    raise;'#10'  end;'#10'  A.StartTransaction;'#10'  Buchen;'#10'  B.StartTransaction;'#10'  try'#10 +
    '    Buchen;'#10'    B.Commit;'#10'  except'#10'    A.Rollback;'#10'    raise;'#10'  end;'#10),
    TChangeSignature.ApplyEdits(Source, Findings[1].Fixes[0].Edits));
  Assert.AreEqual(0, Integer(Length(Findings[2].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[3].Fixes)));
  Assert.AreEqual(3, Integer(Length(TTransactionWithoutRollbackRule.Pairs(''))));
  Assert.AreEqual('BeginTrans', TTransactionWithoutRollbackRule.Pairs('')[2].Start);
end;

procedure TStatementRulesTests.TransactionSilentCases;
begin
  // Rollback im folgenden try, try … finally um try … except, Rollback in anderer Routine, ohne Empfänger.
  TRuleAssert.Silent(TTransactionWithoutRollbackRule.Create, Body('  A.StartTransaction;'#10'  try'#10 +
    '    Buchen;'#10'    A.Commit;'#10'  except'#10'    on E: Exception do'#10'    begin'#10'      A.Rollback;'#10 +
    '      raise;'#10'    end;'#10'  end;'#10'  B.StartTransaction;'#10'  try'#10'    try'#10'      Buchen;'#10 +
    '      B.Commit;'#10'    except'#10'      B.Rollback;'#10'      raise;'#10'    end;'#10'  finally'#10 +
    '    Aufraeumen;'#10'  end;'#10'  StartTransaction;'#10));
  TRuleAssert.Silent(TTransactionWithoutRollbackRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TForm1.BeginnenClick(Sender: TObject);'#10'begin'#10'  Db.StartTransaction;'#10'end;'#10 +
    'procedure TForm1.VerwerfenClick(Sender: TObject);'#10'begin'#10'  Db.Rollback;'#10'end;'#10'end.');
end;

procedure TStatementRulesTests.TransactionOptions;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
  Pairs: TArray<TTransactionPair>;
begin
  Pairs := TTransactionWithoutRollbackRule.Pairs('{"pairs": [{"start": "Beginnen", "commit": "Festschreiben", ' +
    '"rollback": "Verwerfen"}]}');
  Assert.AreEqual(1, Integer(Length(Pairs)));
  Assert.AreEqual('Verwerfen', Pairs[0].Rollback);
  Source := Body('  Db.Beginnen;'#10'  Buchen;'#10'  Db.StartTransaction;'#10'  Buchen;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TTransactionWithoutRollbackRule.Create, Source))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TTransactionWithoutRollbackRule.Create, Source,
    '{"rules": {"transaction-without-rollback": {"pairs": [{"start": "Beginnen", "commit": "Festschreiben", ' +
    '"rollback": "Verwerfen"}]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTransactionWithoutRollbackRule.Create, Source,
    '{"rules": {"transaction-without-rollback": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTransactionWithoutRollbackRule.Create, Source,
    '{"rules": {"transaction-without-rollback": {"exclude": ["Source/*.pas"]}}}', 'Source/Daten.pas'))));
  TConfigurationParser.Parse('{"rules": {"transaction-without-rollback": {"pairs": [{"open": "A", "close": "B"}]}}}',
    Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"transaction-without-rollback": {"pairs": [{"start": "A", "commit": "B", ' +
    '"rollback": "C"}]}, "pair-without-finally": {"pairs": [{"open": "A", "close": "B"}]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

function Konto(const AStatements: string): string;
begin
  Result := 'unit Konten;'#10'interface'#10'implementation'#10'function TKonto.Saldo: Currency;'#10'begin'#10 +
    AStatements + 'end;'#10'end.';
end;

procedure TStatementRulesTests.ComparisonAsStatementIssueExample;
const
  Statements = '  Result = 0;'#10'  for var B in FBuchungen do'#10'    Result := Result + B.Betrag;'#10;
  Fixed = '  Result := 0;'#10'  for var B in FBuchungen do'#10'    Result := Result + B.Betrag;'#10;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto(Statements));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(ComparisonAsStatementRuleId, Findings[0].RuleId);
  Assert.AreEqual('Vergleich als Anweisung (wie E2014); gemeint ist wohl Result := 0.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(12, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('= durch := ersetzen', Findings[0].Fixes[0].Title);
  Text := TChangeSignature.ApplyEdits(Konto(Statements), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Konto(Fixed), Text);
  TRuleAssert.Silent(TComparisonAsStatementRule.Create, Text);
end;

procedure TStatementRulesTests.ComparisonAsStatementVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Feld, Element, Zeiger und Anweisung nach then: jeweils mit Korrektur.
  Findings := TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto('  FAktiv = True;'#10 +
    '  FWerte[I] = 2;'#10'  P^ = 3;'#10'  if Neu then Self.FName = '''';'#10'  (Result = 1);'#10));
  Assert.AreEqual(5, Integer(Length(Findings)));
  Assert.AreEqual('Vergleich als Anweisung (wie E2014); gemeint ist wohl FAktiv := True.', Findings[0].Message);
  Assert.AreEqual('Vergleich als Anweisung (wie E2014); gemeint ist wohl Self.FName := ''''.', Findings[3].Message);
  Assert.AreEqual(1, Integer(Length(Findings[4].Fixes)));
  Assert.AreEqual(Konto('  FAktiv := True;'#10'  FWerte[I] = 2;'#10'  P^ = 3;'#10 +
    '  if Neu then Self.FName = '''';'#10'  (Result = 1);'#10),
    TChangeSignature.ApplyEdits(Konto('  FAktiv = True;'#10'  FWerte[I] = 2;'#10'  P^ = 3;'#10 +
    '  if Neu then Self.FName = '''';'#10'  (Result = 1);'#10), Findings[0].Fixes[0].Edits));
  // Aufruf links, andere Vergleiche und Ausdrücke: ohne Korrektur.
  Findings := TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto('  Laden(1) = 2;'#10 +
    '  Result <> 0;'#10'  Result + 1;'#10'  not FAktiv;'#10'  5;'#10));
  Assert.AreEqual(5, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Vergleich als Anweisung (wie E2014); das Ergebnis wird nicht verwendet.', Findings[1].Message);
  Assert.AreEqual('Ausdruck als Anweisung (wie E2014); das Ergebnis wird nicht verwendet.', Findings[2].Message);
  Assert.AreEqual(0, Integer(Length(Findings[2].Fixes)));
  Assert.AreEqual('Ausdruck als Anweisung (wie E2014); das Ergebnis wird nicht verwendet.', Findings[4].Message);
  // Mehrzeiliger Vorschlag: Leerraum zusammengefasst.
  Findings := TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto('  Result ='#10'    0;'#10));
  Assert.AreEqual('Vergleich als Anweisung (wie E2014); gemeint ist wohl Result := 0.', Findings[0].Message);
end;

procedure TStatementRulesTests.ComparisonAsStatementSilentCases;
begin
  // Zuweisungen, Bedingungen, generische Aufrufe und Typumwandlungen.
  TRuleAssert.Silent(TComparisonAsStatementRule.Create, Konto('  Result := 0;'#10 +
    '  if Result = 0 then'#10'    Exit;'#10'  FAktiv := Result = 0;'#10'  Assert.AreEqual<Integer>(1, 2);'#10 +
    '  TFoo.Bar<Integer>(1);'#10'  (Sender as TButton).Click;'#10'  while not FAktiv do'#10'    Laden;'#10));
end;

procedure TStatementRulesTests.ComparisonAsStatementOffAndExclude;
const
  Statements = '  Result = 0;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto(Statements),
    '{"rules": {"comparison-as-statement": "off"}}', 'Konten.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto(Statements),
    '{"rules": {"group:compiler": "off"}}', 'Konten.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto(Statements),
    '{"rules": {"comparison-as-statement": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Konten.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TComparisonAsStatementRule.Create, Konto(Statements),
    '{"rules": {"comparison-as-statement": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Konten.pas'))));
end;

function Vorgang(const ACase: string): string;
begin
  Result := 'unit Vorgaenge;'#10'interface'#10'type'#10'  TStatus = (stNeu, stOffen, stGeschlossen);'#10 +
    'implementation'#10'const'#10'  Grenze = 5;'#10'  Danach = Grenze + 1;'#10 +
    'procedure Pruefen(Status: TStatus; Zahl: Integer; Zeichen: Char);'#10'begin'#10 + ACase + 'end;'#10'end.';
end;

procedure TStatementRulesTests.DuplicateCaseLabelIssueExample;
const
  Statements = '  case Status of'#10'    stNeu, stOffen: Bearbeiten;'#10'    stGeschlossen: Archivieren;'#10 +
    '    stOffen: Erinnern;'#10'  end;'#10;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang(Statements));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(DuplicateCaseLabelRuleId, Findings[0].RuleId);
  Assert.AreEqual('stOffen kommt schon in Zeile 12 vor (wie E2030).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(13, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('Zweig mit doppeltem Wert entfernen', Findings[0].Fixes[0].Title);
  Text := TChangeSignature.ApplyEdits(Vorgang(Statements), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Vorgang('  case Status of'#10'    stNeu, stOffen: Bearbeiten;'#10'    stGeschlossen: Archivieren;'#10 +
    '  end;'#10), Text);
  TRuleAssert.Silent(TDuplicateCaseLabelRule.Create, Text);
  // Ein Wert unter mehreren: nur er verschwindet.
  Findings := TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang('  case Status of'#10 +
    '    stNeu: Bearbeiten;'#10'    stOffen, stNeu: Erinnern;'#10'  end;'#10));
  Assert.AreEqual('Doppelten Wert aus dem späteren Zweig entfernen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(Vorgang('  case Status of'#10'    stNeu: Bearbeiten;'#10'    stOffen: Erinnern;'#10'  end;'#10),
    TChangeSignature.ApplyEdits(Vorgang('  case Status of'#10'    stNeu: Bearbeiten;'#10 +
    '    stOffen, stNeu: Erinnern;'#10'  end;'#10), Findings[0].Fixes[0].Edits));
  Findings := TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang('  case Status of'#10 +
    '    stNeu: Bearbeiten;'#10'    stNeu, stOffen: Erinnern;'#10'  end;'#10));
  Assert.AreEqual(Vorgang('  case Status of'#10'    stNeu: Bearbeiten;'#10'    stOffen: Erinnern;'#10'  end;'#10),
    TChangeSignature.ApplyEdits(Vorgang('  case Status of'#10'    stNeu: Bearbeiten;'#10 +
    '    stNeu, stOffen: Erinnern;'#10'  end;'#10), Findings[0].Fixes[0].Edits));
end;

procedure TStatementRulesTests.DuplicateCaseLabelValues;
var
  Findings: TArray<TRuleFinding>;
begin
  // Bereiche, Konstanten, Zeichen und Aufzählungswerte über Bereiche.
  Findings := TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang('  case Zahl of'#10 +
    '    1..5: A;'#10'    3: B;'#10'    Danach: C;'#10'    6: D;'#10'    4..8: E;'#10'  end;'#10 +
    '  case Zeichen of'#10'    ''a'': A;'#10'    #97: B;'#10'    Chr(98), ''b'': C;'#10'  end;'#10 +
    '  case Status of'#10'    stNeu..stOffen: A;'#10'    TStatus.stOffen: B;'#10'  end;'#10));
  Assert.AreEqual(6, Integer(Length(Findings)));
  Assert.AreEqual('3 liegt schon in 1..5 aus Zeile 12 (wie E2030).', Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('6 hat denselben Wert wie Danach aus Zeile 14 (wie E2030).', Findings[1].Message);
  Assert.AreEqual('4..8 überschneidet sich mit 1..5 aus Zeile 12 (wie E2030).', Findings[2].Message);
  Assert.AreEqual(0, Integer(Length(Findings[2].Fixes)));
  Assert.AreEqual('#97 hat denselben Wert wie ''a'' aus Zeile 19 (wie E2030).', Findings[3].Message);
  Assert.AreEqual('''b'' hat denselben Wert wie Chr(98) aus Zeile 21 (wie E2030).', Findings[4].Message);
  Assert.AreEqual('TStatus.stOffen liegt schon in stNeu..stOffen aus Zeile 24 (wie E2030).', Findings[5].Message);
end;

procedure TStatementRulesTests.DuplicateCaseLabelVariantRecord;
const
  Source = 'unit Formen;'#10'interface'#10'type'#10'  TForm = record'#10'    case Art: Integer of'#10 +
    '      0: (Radius: Double);'#10'      1, 2: (Breite, Hoehe: Double);'#10'      2: (Seite: Double);'#10 +
    '  end;'#10'implementation'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('2 kommt schon in Zeile 7 vor (wie E2027).', Findings[0].Message);
  Assert.AreEqual(StringReplace(Source, #10'      2: (Seite: Double);', '', []),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
end;

procedure TStatementRulesTests.DuplicateCaseLabelFromIndex;
const
  Source = 'unit Auftraege;'#10'interface'#10'uses'#10'  Grenzen;'#10'implementation'#10 +
    'procedure P(Zahl: Integer; Farbe: TFarbe);'#10'begin'#10'  case Zahl of'#10'    Oben: A;'#10'    10: B;'#10 +
    '    Mitte: C;'#10'    3: D;'#10'  end;'#10'  case Farbe of'#10'    fRot..fBlau: A;'#10'    fGruen: B;'#10'  end;'#10 +
    'end;'#10'end.';
var
  Index: ISymbolIndex;
  Findings: TArray<TRuleFinding>;
begin
  // Konstanten und Aufzählung aus einer anderen Unit; Oben verweist dort auf Basis.
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Grenzen;'#10'interface'#10'type'#10 +
    '  TFarbe = (fRot, fGruen, fBlau);'#10'const'#10'  Basis = 4;'#10'  Oben = Basis * 2 + 2;'#10 +
    '  Mitte = Basis - 1;'#10'implementation'#10'end.', 'C:\Projekt\Grenzen.pas', nil));
  Findings := TRuleAssert.IndexFindings(TDuplicateCaseLabelRule.Create, Source, Index, '', 'Auftraege.pas');
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('10 hat denselben Wert wie Oben aus Zeile 9 (wie E2030).', Findings[0].Message);
  Assert.AreEqual('3 hat denselben Wert wie Mitte aus Zeile 11 (wie E2030).', Findings[1].Message);
  Assert.AreEqual('fGruen liegt schon in fRot..fBlau aus Zeile 15 (wie E2030).', Findings[2].Message);
end;

procedure TStatementRulesTests.DuplicateCaseLabelSilentCases;
begin
  // Verschiedene Werte, unbekannte Namen und Aufzählungen mit eigenen Werten.
  TRuleAssert.Silent(TDuplicateCaseLabelRule.Create, Vorgang('  case Status of'#10 +
    '    stNeu, stOffen: Bearbeiten;'#10'    stGeschlossen: Archivieren;'#10'  else'#10'    Erinnern;'#10'  end;'#10 +
    '  case Zahl of'#10'    1..5: A;'#10'    6..9, Grenze + 5: B;'#10'    Unbekannt: C;'#10'    Fremd: D;'#10 +
    '    -1: E;'#10'  end;'#10 +
    '  case Zeichen of'#10'    ''ä'': A;'#10'    ''ö'': B;'#10'    ''A'': C;'#10'    ''a'', ''Ä'': D;'#10'  end;'#10));
  // Zweige von {$IFDEF} und {$ELSE} werden nie zusammen übersetzt; innerhalb eines Zweigs zählt es.
  TRuleAssert.Silent(TDuplicateCaseLabelRule.Create, Vorgang('  case Zahl of'#10'{$IFDEF DEBUG}'#10 +
    '    1: A;'#10'{$ELSEIF Defined(TEST)}'#10'    1: B;'#10'{$ELSE}'#10'    1: C;'#10'{$ENDIF}'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang('  case Zahl of'#10 +
    '    1: A;'#10'{$IFDEF DEBUG}'#10'    1: B;'#10'{$ENDIF}'#10'  end;'#10)))));
  TRuleAssert.Silent(TDuplicateCaseLabelRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TArt = (aEins = 1, aAuch = 1);'#10'implementation'#10'procedure P(A: TArt);'#10'begin'#10 +
    '  case A of'#10'    aEins: X;'#10'    aAuch: Y;'#10'  end;'#10'end;'#10'end.');
end;

procedure TStatementRulesTests.DuplicateCaseLabelOffAndExclude;
const
  Statements = '  case Zahl of'#10'    1: A;'#10'    1: B;'#10'  end;'#10;
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang(Statements)))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang(Statements),
    '{"rules": {"duplicate-case-label": "off"}}', 'Vorgaenge.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang(Statements),
    '{"rules": {"group:compiler": "off"}}', 'Vorgaenge.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateCaseLabelRule.Create, Vorgang(Statements),
    '{"rules": {"duplicate-case-label": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Vorgaenge.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TStatementRulesTests);

end.
