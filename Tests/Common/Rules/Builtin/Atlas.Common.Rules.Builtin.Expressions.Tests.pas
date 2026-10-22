unit Atlas.Common.Rules.Builtin.Expressions.Tests;

// Tests der Regel operator-precedence (#911): not vor in und Vergleichen bei
// Aufzählungen und Ganzzahlen, Klammern als Korrektur, keine Meldung bei
// Boolean, unbekanntem Typ und geklammerter Form, Abschalten und Ausnahmen;
// duplicate-condition (#928); string-index-base (#951).

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
    [Test]
    procedure DuplicateConditionIssueExample;
    [Test]
    procedure DuplicateConditionVariants;
    [Test]
    procedure DuplicateConditionSilentCases;
    [Test]
    procedure StringIndexBaseIssueExample;
    [Test]
    procedure StringIndexBaseVariants;
    [Test]
    procedure StringIndexBaseSilentCases;
    [Test]
    procedure StringIndexBaseOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
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

function Stufen(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Einstufen(Betrag: Integer; Wert: Double; A, B: Boolean);'#10'var'#10'  Stufe: Integer;'#10 +
    'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TExpressionRulesTests.DuplicateConditionIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDuplicateConditionRule.Create, Stufen('  if Betrag > 1000 then'#10 +
    '    Stufe := 3'#10'  else if Betrag > 500 then'#10'    Stufe := 2'#10'  else if Betrag  >  1000 then'#10 +
    '    Stufe := 1;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Gleiche Bedingung wie in Zeile 8; dieser Zweig wird nie erreicht.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
  Assert.IsTrue(Findings[0].Fixes[0].HasJump);
  Assert.AreEqual(7, Findings[0].Fixes[0].JumpTo.Line);
  TRuleAssert.Silent(TDuplicateConditionRule.Create, Stufen('  if Betrag > 1000 then'#10'    Stufe := 3'#10 +
    '  else if Betrag > 500 then'#10'    Stufe := 2'#10'  else if Betrag > 100 then'#10'    Stufe := 1;'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateConditionRule.Create,
    Stufen('  if A and A then'#10'    Exit;'), '{"rules": {"duplicate-condition": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateConditionRule.Create,
    Stufen('  if A and A then'#10'    Exit;'), '{"rules": {"duplicate-condition": {"exclude": ["Alt/*.pas"]}}}',
    'Alt/U.pas'))));
end;

procedure TExpressionRulesTests.DuplicateConditionVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Gleiche Zweige, A and B and a, X = X.
  Findings := TRuleAssert.Findings(TDuplicateConditionRule.Create, Stufen('  if A then'#10'    Stufe := 1'#10 +
    '  else'#10'    Stufe := 1;'#10'  if A and (B and a) then'#10'    Exit;'#10'  if Betrag = Betrag then'#10 +
    '    Exit;'#10'  if Betrag < (Betrag) then'#10'    Exit;'));
  Assert.AreEqual(4, Integer(Length(Findings)));
  Assert.AreEqual('then- und else-Zweig sind gleich; die Bedingung hat keine Wirkung.', Findings[0].Message);
  Assert.AreEqual('a steht zweimal in derselben and-Verknüpfung; vermutlich ein Kopierfehler.', Findings[1].Message);
  Assert.AreEqual('Betrag wird mit sich selbst verglichen; das Ergebnis ist immer True.', Findings[2].Message);
  Assert.AreEqual('Betrag wird mit sich selbst verglichen; das Ergebnis ist immer False.', Findings[3].Message);
end;

procedure TExpressionRulesTests.DuplicateConditionSilentCases;
begin
  // NaN-Prüfung, Lesen aus einem Strom, verschiedene Operatoren, else-if mit begin.
  TRuleAssert.Silent(TDuplicateConditionRule.Create, Stufen('  if Wert <> Wert then'#10'    Exit;'#10 +
    '  if Leser.Next = ''x'' then'#10'    Stufe := 1'#10'  else if Leser.Next = ''x'' then'#10'    Stufe := 2;'#10 +
    '  if A and B or A then'#10'    Exit;'#10'  if A then'#10'    Stufe := 1'#10'  else'#10'    Stufe := 2;'#10 +
    '  if A then'#10'    Stufe := 1'#10'  else'#10'  begin'#10'    if A then'#10'      Stufe := 2;'#10'  end;'));
  // Aufruf mit var-Parameter dazwischen, Singleton-Vergleich.
  TRuleAssert.Silent(TDuplicateConditionRule.Create, Stufen('  if Take(Stufe, ''.'') and Take(Stufe, ''.'') then'#10 +
    '    Exit;'#10'  if (Betrag = 0) and not Pruefen(Betrag) and (Betrag = 0) then'#10'    Exit;'#10 +
    '  if TKatalog.Shared = TKatalog.Shared then'#10'    Exit;'));
  // Reine Funktionen zählen weiter.
  TRuleAssert.Reports(TDuplicateConditionRule.Create, Stufen('  if SameText(S, ''a'') or SameText(S, ''a'') then'#10 +
    '    Exit;'));
end;

function Zeilen(const AStatements: string): string;
begin
  Result := 'unit Zeilen;'#10'interface'#10'implementation'#10'procedure Lesen(const Zeile: string; Werte: TArray<Integer>);'#10 +
    'var'#10'  Felder: string;'#10'  Puffer: ShortString;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

/// <summary>Wendet alle Änderungen der Korrektur an, von hinten nach vorn (Zeilen mit #10).</summary>
function ApplyFixes(const AText: string; const AFindings: TArray<TRuleFinding>): string;
var
  Index: Integer;
  Edit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Position: Integer;
  begin
    Position := 0;
    for Line := 1 to APosition.Line do
      Position := Pos(#10, AText, Position + 1);
    Result := Position + APosition.Character;
  end;

begin
  Result := AText;
  for Index := High(AFindings) downto 0 do
  begin
    Edit := AFindings[Index].Fixes[0].Edits[0];
    Result := Copy(Result, 1, OffsetOf(Edit.Range.StartPos)) + Edit.NewText +
      Copy(Result, OffsetOf(Edit.Range.EndPos) + 1, MaxInt);
  end;
end;

procedure TExpressionRulesTests.StringIndexBaseIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Zeilen('  if Pos('';'', Zeile) > -1 then'#10'    Felder := Copy(Zeile, 0, Pos('';'', Zeile) - 1);'#10);
  Findings := TRuleAssert.Findings(TStringIndexBaseRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('string-index-base', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('Pos liefert 0 bei keinem Treffer; der Vergleich > -1 ist immer wahr.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Vergleich auf "> 0" korrigieren', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Copy zählt Zeichen ab 1; der Startwert 0 wirkt nur zufällig wie 1.', Findings[1].Message);
  Assert.AreEqual('Startwert 1', Findings[1].Fixes[0].Title);
  Fixed := ApplyFixes(Source, Findings);
  Assert.AreEqual(Zeilen('  if Pos('';'', Zeile) > 0 then'#10'    Felder := Copy(Zeile, 1, Pos('';'', Zeile) - 1);'#10),
    Fixed);
  TRuleAssert.Silent(TStringIndexBaseRule.Create, Fixed);
end;

procedure TExpressionRulesTests.StringIndexBaseVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TStringIndexBaseRule.Create, Zeilen('  Delete(Felder, 0, 1);'#10));
  Assert.AreEqual('Delete zählt Zeichen ab 1; mit dem Startwert 0 löscht es nichts.', Findings[0].Message);
  TRuleAssert.Reports(TStringIndexBaseRule.Create, Zeilen('  Insert(''x'', Felder, 0);'#10));
  TRuleAssert.Reports(TStringIndexBaseRule.Create, Zeilen('  Delete(Puffer, 0, 1);'#10));
  TRuleAssert.Reports(TStringIndexBaseRule.Create, Zeilen('  Felder := Copy(Edit1.Text, 0, 2);'#10));
  Findings := TRuleAssert.Findings(TStringIndexBaseRule.Create, Zeilen('  if Pos(''a'', Zeile) >= 0 then Exit;'#10));
  Assert.AreEqual('Pos liefert 0 bei keinem Treffer; der Vergleich >= 0 ist immer wahr.', Findings[0].Message);
  Findings := TRuleAssert.Findings(TStringIndexBaseRule.Create,
    Zeilen('  if System.StrUtils.PosEx(''a'', Zeile, 2) = -1 then Exit;'#10));
  Assert.AreEqual('PosEx liefert 0 bei keinem Treffer; der Vergleich = -1 ist nie wahr.', Findings[0].Message);
  Assert.AreEqual('Vergleich auf "= 0" korrigieren', Findings[0].Fixes[0].Title);
  TRuleAssert.Reports(TStringIndexBaseRule.Create, Zeilen('  if Pos(''a'', Zeile) <> -1 then Exit;'#10));
  // String-Helper: nullbasiert.
  Findings := TRuleAssert.Findings(TStringIndexBaseRule.Create, Zeilen('  if Zeile.IndexOf(''a'') > 0 then Exit;'#10));
  Assert.AreEqual('IndexOf zählt ab 0 und liefert -1 bei keinem Treffer; der Vergleich > 0 übersieht den Treffer ' +
    'am Anfang.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('Vergleich auf ">= 0" korrigieren', Findings[0].Fixes[0].Title);
  TRuleAssert.Reports(TStringIndexBaseRule.Create, Zeilen('  if Zeile.IndexOf(''a'') < 1 then Exit;'#10));
end;

procedure TExpressionRulesTests.StringIndexBaseSilentCases;
begin
  // Richtige Formen.
  TRuleAssert.Silent(TStringIndexBaseRule.Create, Zeilen('  if Pos('';'', Zeile) > 0 then'#10 +
    '    Felder := Copy(Zeile, 1, 2);'#10'  if Zeile.IndexOf(''a'') >= 0 then Exit;'#10 +
    '  if Zeile.IndexOf(''a'') = -1 then Exit;'#10'  if Pos(''a'', Zeile) = 0 then Exit;'#10 +
    '  if Zeile.LastIndexOf(''.'') > 0 then Exit;'#10));
  // Dynamische Arrays zählen ab 0; unbekannte Typen bleiben stumm.
  TRuleAssert.Silent(TStringIndexBaseRule.Create, Zeilen('  Werte := Copy(Werte, 0, 2);'#10 +
    '  Delete(Werte, 0, 1);'#10'  Insert(1, Werte, 0);'#10'  Delete(Unbekannt, 0, 1);'#10));
  // Methoden und Rechnungen.
  TRuleAssert.Silent(TStringIndexBaseRule.Create, Zeilen('  Liste.Delete(0);'#10'  Felder := Liste.Copy(0, 1);'#10 +
    '  if Pos(''a'', Zeile) - 1 > -1 then Exit;'#10'  if 1 + Pos(''a'', Zeile) >= 0 then Exit;'#10 +
    '  if Pos(''a'', Zeile) > -1 + Versatz then Exit;'#10));
end;

procedure TExpressionRulesTests.StringIndexBaseOffAndExclude;
var
  Source: string;
begin
  Source := Zeilen('  Delete(Felder, 0, 1);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIndexBaseRule.Create, Source,
    '{"rules": {"string-index-base": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIndexBaseRule.Create, Source,
    '{"rules": {"string-index-base": {"exclude": ["Source/*.pas"]}}}', 'Source/Zeilen.pas'))));
  Assert.IsTrue(TStringIndexBaseRule.IsStringType('String[20]'));
  Assert.IsTrue(TStringIndexBaseRule.IsStringType('AnsiString'));
  Assert.IsFalse(TStringIndexBaseRule.IsStringType('TArray<Integer>'));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionRulesTests);

end.
