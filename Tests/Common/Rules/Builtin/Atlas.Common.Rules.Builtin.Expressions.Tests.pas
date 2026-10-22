unit Atlas.Common.Rules.Builtin.Expressions.Tests;

// Tests der Regel operator-precedence (#911): not vor in und Vergleichen bei
// Aufzählungen und Ganzzahlen, Klammern als Korrektur, keine Meldung bei
// Boolean, unbekanntem Typ und geklammerter Form, Abschalten und Ausnahmen;
// duplicate-condition (#928); string-index-base (#951); null-compare (#953);
// pos-arguments-swapped (#1045); integer-division-to-float (#1046).

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
    [Test]
    procedure NullCompareIssueExample;
    [Test]
    procedure NullCompareVariants;
    [Test]
    procedure NullCompareSilentCases;
    [Test]
    procedure NullCompareOffAndExclude;
    [Test]
    procedure PosArgumentsSwappedIssueExample;
    [Test]
    procedure PosArgumentsSwappedVariants;
    [Test]
    procedure PosArgumentsSwappedSilentCases;
    [Test]
    procedure PosArgumentsSwappedOptions;
    [Test]
    procedure IntegerDivisionIssueExample;
    [Test]
    procedure IntegerDivisionVariants;
    [Test]
    procedure IntegerDivisionSilentCases;
    [Test]
    procedure IntegerDivisionOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Parser,
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

function Kunden(const AStatements: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'implementation'#10'uses System.Variants, Data.DB;'#10 +
    'procedure Berechnen(qryKunde: TDataSet; Feld: TDateField; Wert: Variant; var Alter: Integer);'#10 +
    'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TExpressionRulesTests.NullCompareIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Kunden('  if qryKunde.FieldByName(''Geburtstag'').Value = Null then'#10'    Alter := 0;'#10);
  Findings := TRuleAssert.Findings(TNullCompareRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('null-compare', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Der Vergleich mit Null hängt von NullEqualityRule ab (ncrStrict: nie wahr, ncrError: ' +
    'Exception); IsNull prüft das Feld unabhängig davon.', Findings[0].Message);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('Durch "qryKunde.FieldByName(''Geburtstag'').IsNull" ersetzen', Findings[0].Fixes[0].Title);
  Fixed := ApplyFixes(Source, Findings);
  Assert.AreEqual(Kunden('  if qryKunde.FieldByName(''Geburtstag'').IsNull then'#10'    Alter := 0;'#10), Fixed);
  TRuleAssert.Silent(TNullCompareRule.Create, Fixed);
end;

procedure TExpressionRulesTests.NullCompareVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Variant: VarIsNull; <> mit not; Null links.
  Source := Kunden('  if Wert <> Null then Exit;'#10'  if (Null = Feld.Value) and (Alter > 0) then Exit;'#10 +
    '  Alter := Ord(qryKunde.Fields[0].Value = Null);'#10);
  Findings := TRuleAssert.Findings(TNullCompareRule.Create, Source);
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Der Vergleich mit Null hängt von NullEqualityRule ab (ncrStrict: nie wahr, ncrError: ' +
    'Exception); VarIsNull prüft den Wert unabhängig davon.', Findings[0].Message);
  Assert.AreEqual(Kunden('  if not VarIsNull(Wert) then Exit;'#10'  if (Feld.IsNull) and (Alter > 0) then Exit;'#10 +
    '  Alter := Ord(qryKunde.Fields[0].IsNull);'#10), ApplyFixes(Source, Findings));
  // "not X = Null" bindet als "(not X) = Null": Meldung ohne Korrektur.
  Findings := TRuleAssert.Findings(TNullCompareRule.Create, Kunden('  if not Wert = Null then Exit;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TExpressionRulesTests.NullCompareSilentCases;
begin
  // Richtige Formen, Zuweisung von Null, nil, andere Operatoren und andere Bindung.
  TRuleAssert.Silent(TNullCompareRule.Create, Kunden('  if VarIsNull(Wert) or Feld.IsNull then Exit;'#10 +
    '  Wert := Null;'#10'  if qryKunde = nil then Exit;'#10'  if (Alter > 0) and Wert = Null then Exit;'#10 +
    '  if Wert = Null + 1 then Exit;'#10'  if Wert = Werte.Null then Exit;'#10));
  Assert.IsTrue(TNullCompareRule.IsDataType('TStringField'));
  Assert.IsTrue(TNullCompareRule.IsDataType('Data.DB.TParam'));
  Assert.IsTrue(TNullCompareRule.IsDataType('TFDParam'));
  Assert.IsFalse(TNullCompareRule.IsDataType('Variant'));
  Assert.IsFalse(TNullCompareRule.IsDataType('TFieldDef'));
end;

procedure TExpressionRulesTests.NullCompareOffAndExclude;
var
  Source: string;
begin
  Source := Kunden('  if Wert = Null then Exit;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TNullCompareRule.Create, Source,
    '{"rules": {"null-compare": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TNullCompareRule.Create, Source,
    '{"rules": {"null-compare": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunden.pas'))));
end;

function Suche(const AStatements: string): string;
begin
  Result := 'unit Suche;'#10'interface'#10'uses System.StrUtils;'#10'implementation'#10 +
    'procedure Finden(const Zeile: string; Zeichen: Char; Feld: TEdit);'#10'var'#10'  Treffer: Integer;'#10 +
    '  Gefunden: Boolean;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TExpressionRulesTests.PosArgumentsSwappedIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Suche('  if Pos(Zeile, '';'') > 0 then'#10'    Treffer := 1;'#10);
  Findings := TRuleAssert.Findings(TPosArgumentsSwappedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('pos-arguments-swapped', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('Pos(Teil, Text): vermutlich vertauscht, gesucht wird '';'' in Zeile.', Findings[0].Message);
  Assert.AreEqual(9, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(9, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('Argumente tauschen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Fixed := ApplyFixes(Source, Findings);
  Assert.AreEqual(Suche('  if Pos('';'', Zeile) > 0 then'#10'    Treffer := 1;'#10), Fixed);
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Fixed);
end;

procedure TExpressionRulesTests.PosArgumentsSwappedVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // ContainsText erwartet den Text zuerst.
  Findings := TRuleAssert.Findings(TPosArgumentsSwappedRule.Create,
    Suche('  Gefunden := ContainsText('', '', Zeile);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('ContainsText(Text, Teil): vermutlich vertauscht, gesucht wird '', '' in Zeile.',
    Findings[0].Message);
  Assert.AreEqual('Zeile, '', ''', Findings[0].Fixes[0].Edits[0].NewText);
  // PosEx mit drittem Argument, StartsText, Kommentar zwischen den Argumenten bleibt erhalten.
  Findings := TRuleAssert.Findings(TPosArgumentsSwappedRule.Create,
    Suche('  Treffer := PosEx(Zeile, #9, 3);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('#9, Zeile', Findings[0].Fixes[0].Edits[0].NewText);
  Findings := TRuleAssert.Findings(TPosArgumentsSwappedRule.Create,
    Suche('  Gefunden := System.StrUtils.StartsText(Trim(Zeile), {Kopf} ''//'');'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('''//'', {Kopf} Trim(Zeile)', Findings[0].Fixes[0].Edits[0].NewText);
  // .Text, Verkettung und '''' als ein Zeichen.
  TRuleAssert.Reports(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos(Feld.Text, ''.'');'#10));
  TRuleAssert.Reports(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos(Zeile + ''x'', '''''''');'#10));
  TRuleAssert.Reports(TPosArgumentsSwappedRule.Create, Suche('  Gefunden := EndsStr(Zeile, ''\'');'#10));
end;

procedure TExpressionRulesTests.PosArgumentsSwappedSilentCases;
begin
  // Richtige Reihenfolge, Zeichen in einer Trennerliste, unbekannter Typ, langes Literal, zwei Literale.
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos('';'', Zeile);'#10 +
    '  Gefunden := ContainsText(Zeile, '';'');'#10'  Gefunden := StartsText(''//'', Zeile);'#10));
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos(Zeichen, '';,'');'#10));
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos(Unbekannt, '';'');'#10));
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos(Zeile, ''Ende'');'#10));
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos(''ab'', '';'');'#10));
  // Eigene Methode eines Objekts und Zeichen + Zeichen.
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Liste.Pos(Zeile, '';'');'#10));
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Suche('  Treffer := Pos(Zeichen + Zeichen, '';'');'#10));
  Assert.AreEqual(1, TPosArgumentsSwappedRule.LiteralLength(''''''''''));
  Assert.AreEqual(3, TPosArgumentsSwappedRule.LiteralLength('''a''#13#$0A'));
  Assert.AreEqual(-1, TPosArgumentsSwappedRule.LiteralLength('X'));
end;

procedure TExpressionRulesTests.PosArgumentsSwappedOptions;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Suche('  Treffer := Pos(Zeile, ''END;'');'#10);
  TRuleAssert.Silent(TPosArgumentsSwappedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TPosArgumentsSwappedRule.Create, Source,
    '{"rules": {"pos-arguments-swapped": {"maxLiteralLength": 4}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPosArgumentsSwappedRule.Create,
    Suche('  Treffer := Pos(Zeile, ''//'');'#10), '{"rules": {"pos-arguments-swapped": {"maxLiteralLength": 1}}}'))));
  Source := Suche('  Treffer := Pos(Zeile, '';'');'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPosArgumentsSwappedRule.Create, Source,
    '{"rules": {"pos-arguments-swapped": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPosArgumentsSwappedRule.Create, Source,
    '{"rules": {"pos-arguments-swapped": {"exclude": ["Source/*.pas"]}}}', 'Source/Suche.pas'))));
  TConfigurationParser.Parse('{"rules": {"pos-arguments-swapped": {"maxLiteralLength": 0}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"maxLiteralLength" muss eine ganze Zahl ab 1 sein', Issues[0].Message);
end;

function Statistik(const AStatements: string): string;
begin
  Result := 'unit Statistik;'#10'interface'#10'implementation'#10 +
    'procedure Rechnen(Summe, Anzahl: Integer; Teil, Gesamt: Int64);'#10'var'#10'  Schnitt: Double;'#10 +
    '  Prozent: Single;'#10'  Ganz: Integer;'#10'  Datum: TDateTime;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TExpressionRulesTests.IntegerDivisionIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Statistik('  Schnitt := Summe div Anzahl;'#10);
  Findings := TRuleAssert.Findings(TIntegerDivisionToFloatRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('integer-division-to-float', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('div rechnet ganzzahlig; Schnitt ist Double und verliert die Nachkommastellen.',
    Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(13, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('div durch / ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Fixed := ApplyFixes(Source, Findings);
  Assert.AreEqual(Statistik('  Schnitt := Summe / Anzahl;'#10), Fixed);
  TRuleAssert.Silent(TIntegerDivisionToFloatRule.Create, Fixed);
end;

procedure TExpressionRulesTests.IntegerDivisionVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TIntegerDivisionToFloatRule.Create,
    Statistik('  Prozent := Teil div Gesamt * 100;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('div rechnet ganzzahlig; Prozent ist Single und verliert die Nachkommastellen.',
    Findings[0].Message);
  Assert.AreEqual(Statistik('  Prozent := Teil / Gesamt * 100;'#10),
    ApplyFixes(Statistik('  Prozent := Teil div Gesamt * 100;'#10), Findings));
  // Klammern, Vorzeichen, Summe, Inline-Variable und Result einer Funktion.
  TRuleAssert.Reports(TIntegerDivisionToFloatRule.Create, Statistik('  Schnitt := -(Summe div Anzahl) + 0.5;'#10));
  TRuleAssert.Reports(TIntegerDivisionToFloatRule.Create, Statistik('  var Mittel: Extended := Summe div 2;'#10));
  TRuleAssert.Reports(TIntegerDivisionToFloatRule.Create, 'unit F;'#10'interface'#10'implementation'#10 +
    'function Mittel(A, B: Integer): Double;'#10'begin'#10'  Result := A div B;'#10'end;'#10'end.');
  TRuleAssert.Reports(TIntegerDivisionToFloatRule.Create, 'unit F;'#10'interface'#10'type'#10 +
    '  TWert = class'#10'    FAnteil: Currency;'#10'    procedure Setzen(A, B: Integer);'#10'  end;'#10 +
    'implementation'#10'procedure TWert.Setzen(A, B: Integer);'#10'begin'#10'  Self.FAnteil := A div B;'#10 +
    'end;'#10'end.');
end;

procedure TExpressionRulesTests.IntegerDivisionSilentCases;
begin
  // Richtige Division, Ganzzahlziel, Aufruf, mod, TDateTime, unbekanntes Ziel.
  TRuleAssert.Silent(TIntegerDivisionToFloatRule.Create, Statistik('  Schnitt := Summe / Anzahl;'#10 +
    '  Ganz := Summe div Anzahl;'#10'  Schnitt := Round(Summe div Anzahl);'#10 +
    '  Schnitt := (Summe div Anzahl) mod 2;'#10'  Datum := Summe div 86400;'#10'  Fremd := Summe div Anzahl;'#10));
  // Funktion mit Ganzzahlergebnis und with-Block.
  TRuleAssert.Silent(TIntegerDivisionToFloatRule.Create, 'unit F;'#10'interface'#10'implementation'#10 +
    'function Mittel(A, B: Integer): Integer;'#10'begin'#10'  Result := A div B;'#10'end;'#10'end.');
  TRuleAssert.Silent(TIntegerDivisionToFloatRule.Create, Statistik('  with Liste do'#10 +
    '    Schnitt := Summe div Anzahl;'#10));
  // Ausdrücklich gewandelte Operanden: ganzzahlige Division ist gewollt.
  TRuleAssert.Silent(TIntegerDivisionToFloatRule.Create, Statistik('  Schnitt := Trunc(Schnitt) div Trunc(Prozent);'#10 +
    '  Schnitt := Summe div (Round(Prozent));'#10));
  Assert.IsTrue(TIntegerDivisionToFloatRule.IsFractional('Currency'));
  Assert.IsFalse(TIntegerDivisionToFloatRule.IsFractional('TDateTime'));
end;

procedure TExpressionRulesTests.IntegerDivisionOffAndExclude;
var
  Source: string;
begin
  Source := Statistik('  Schnitt := Summe div Anzahl;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TIntegerDivisionToFloatRule.Create, Source,
    '{"rules": {"integer-division-to-float": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TIntegerDivisionToFloatRule.Create, Source,
    '{"rules": {"group:find-bugs": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TIntegerDivisionToFloatRule.Create, Source,
    '{"rules": {"integer-division-to-float": {"exclude": ["Source/*.pas"]}}}', 'Source/Statistik.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionRulesTests);

end.
