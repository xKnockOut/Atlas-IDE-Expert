unit Atlas.Common.Rules.Builtin.Loops.Tests;

// Tests der Regel for-variable-misuse (#1009): Beispiel aus dem Issue mit
// Korrektur nach while, Zuweisung mit einzelner Anweisung als Rumpf, downto
// und Continue ohne Korrektur, var-Parameter einer Routine der Datei (W1015),
// Feld und Variable der umgebenden Routine (E1019), globale Variable (W1019) mit
// Korrektur "for var", stille Fälle, Abschalten, Gruppe und Ausnahmen.
// Tests der Regel for-variable-after-loop (#1010): Beispiel aus dem Issue mit
// Korrektur nach while, Lesen erst nach weiteren Anweisungen und in einer
// Bedingung, stille Fälle (Zuweisung vorher, for var, Feld, nur im Rumpf,
// neue Schleife, Argument einer unbekannten Routine), Abschalten, Gruppe und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TForVariableMisuseTests = class
  public
    [Test]
    procedure IssueExampleWithWhileFix;
    [Test]
    procedure AssignmentWithSingleStatementBody;
    [Test]
    procedure DowntoAndContinue;
    [Test]
    procedure VarParameterOfOwnRoutine;
    [Test]
    procedure NonLocalLoopVariables;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure RuleIsRegistered;
  end;

  [TestFixture]
  TForVariableAfterLoopTests = class
  public
    [Test]
    procedure IssueExampleWithWhileFix;
    [Test]
    procedure LaterReadAndCondition;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Loops,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Zeilen(const AStatements: string): string;
begin
  Result := 'unit Zeilen;'#10'interface'#10'type'#10'  TLeser = class'#10'    FIndex: Integer;'#10 +
    '    procedure Lesen(Zeilen: TStrings);'#10'  end;'#10'var'#10'  GZaehler: Integer;'#10 +
    'procedure Weiter(var N: Integer);'#10'implementation'#10'procedure Weiter(var N: Integer);'#10'begin'#10 +
    'end;'#10'procedure TLeser.Lesen(Zeilen: TStrings);'#10'var'#10'  I, J: Integer;'#10'begin'#10 +
    AStatements + 'end;'#10'end.';
end;

{ TForVariableMisuseTests }

procedure TForVariableMisuseTests.IssueExampleWithWhileFix;
const
  cStatements = '  for I := 0 to Zeilen.Count - 1 do'#10'  begin'#10'    if Zeilen[I] = '''' then'#10 +
    '      Inc(I);'#10'  end;'#10;
  cFixed = '  I := 0;'#10'  while I <= Zeilen.Count - 1 do'#10'  begin'#10'    if Zeilen[I] = '''' then'#10 +
    '      Inc(I);'#10'    Inc(I);'#10'  end;'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create, Zeilen(cStatements));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cForVariableMisuseRuleId, mFindings[0].RuleId);
  Assert.AreEqual('Schleifenvariable I darf im Rumpf nicht verändert werden (wie E2081).', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(21, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Auf while-Schleife umstellen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(Zeilen(cFixed), TChangeSignature.ApplyEdits(Zeilen(cStatements), mFindings[0].Fixes[0].Edits));
end;

procedure TForVariableMisuseTests.AssignmentWithSingleStatementBody;
const
  cStatements = '  for var K := 1 to 3 do'#10'    K := K + 1;'#10;
  cFixed = '  var K := 1;'#10'  while K <= 3 do'#10'  begin'#10'    K := K + 1;'#10'    Inc(K);'#10'  end;'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create, Zeilen(cStatements));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Schleifenvariable K darf im Rumpf nicht zugewiesen werden (wie E2081).', mFindings[0].Message);
  Assert.AreEqual(19, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(Zeilen(cFixed), TChangeSignature.ApplyEdits(Zeilen(cStatements), mFindings[0].Fixes[0].Edits));
  // Ohne Semikolon nach der letzten Anweisung im Block ergänzt die Korrektur es.
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create,
    Zeilen('  for I := 1 to 3 do'#10'  begin'#10'    I := 5'#10'  end;'#10));
  Assert.AreEqual(Zeilen('  I := 1;'#10'  while I <= 3 do'#10'  begin'#10'    I := 5;'#10'    Inc(I);'#10'  end;'#10),
    TChangeSignature.ApplyEdits(Zeilen('  for I := 1 to 3 do'#10'  begin'#10'    I := 5'#10'  end;'#10),
    mFindings[0].Fixes[0].Edits));
end;

procedure TForVariableMisuseTests.DowntoAndContinue;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create,
    Zeilen('  for I := 9 downto 0 do'#10'    Dec(I);'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Zeilen('  I := 9;'#10'  while I >= 0 do'#10'  begin'#10'    Dec(I);'#10'    Dec(I);'#10'  end;'#10),
    TChangeSignature.ApplyEdits(Zeilen('  for I := 9 downto 0 do'#10'    Dec(I);'#10), mFindings[0].Fixes[0].Edits));
  // Continue im Rumpf würde das Weiterzählen überspringen: keine Korrektur.
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create,
    Zeilen('  for I := 0 to 9 do'#10'  begin'#10'    if I = 3 then'#10'      Continue;'#10'    I := 7;'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TForVariableMisuseTests.VarParameterOfOwnRoutine;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create,
    Zeilen('  for I := 0 to 9 do'#10'    Weiter(I);'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Schleifenvariable I wird als var-Parameter an Weiter übergeben (wie W1015).', mFindings[0].Message);
  Assert.AreEqual(19, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TForVariableMisuseTests.NonLocalLoopVariables;
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  mSource := Zeilen('  for FIndex := 0 to 9 do'#10'    Zeilen.Add('''');'#10'  for GZaehler := 1 to 2 do'#10 +
    '    Zeilen.Add('''');'#10'  GZaehler := 0;'#10);
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Schleifenvariable FIndex ist ein Feld, keine einfache lokale Variable (wie E1019).',
    mFindings[0].Message);
  Assert.AreEqual(18, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual('for var FIndex verwenden', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(Zeilen('  for var FIndex := 0 to 9 do'#10'    Zeilen.Add('''');'#10'  for GZaehler := 1 to 2 do'#10 +
    '    Zeilen.Add('''');'#10'  GZaehler := 0;'#10), TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits));
  // Eine globale Variable übersetzt Delphi 13 mit Warnung W1019 (Fall Cm.W1019, #1382).
  Assert.AreEqual('Schleifenvariable GZaehler ist eine globale Variable, keine einfache lokale Variable (wie W1019).',
    mFindings[1].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[1].Fixes)), 'GZaehler wird nach der Schleife noch benutzt');
  // Lokale Prozedur mit der Variablen der umgebenden Routine.
  mFindings := TRuleAssert.Findings(TForVariableMisuseRule.Create,
    'unit Zeilen;'#10'interface'#10'implementation'#10'procedure Lesen;'#10'var'#10'  I: Integer;'#10 +
    '  procedure Zaehlen;'#10'  begin'#10'    for I := 0 to 3 do'#10'      Ausgeben(I);'#10'  end;'#10'begin'#10 +
    '  Zaehlen;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Schleifenvariable I ist eine Variable der umgebenden Routine, keine einfache lokale Variable ' +
    '(wie E1019).', mFindings[0].Message);
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
end;

procedure TForVariableMisuseTests.SilentCases;
begin
  // Lesen, andere Variablen ändern, Self.I, Zuweisung nach der Schleife, Wertparameter, anonyme Methode, with,
  // for var, Parameter als Schleifenvariable, unbekannte Routine mit I als Argument.
  TRuleAssert.Silent(TForVariableMisuseRule.Create,
    Zeilen('  for I := 0 to Zeilen.Count - 1 do'#10'  begin'#10'    J := I;'#10'    Inc(J);'#10 +
    '    Zeilen[I] := '''';'#10'    Ausgeben(I);'#10'    Zeilen.Delete(I);'#10'    TThread.Queue(nil, procedure ' +
    'begin Ausgeben(I); end);'#10'  end;'#10'  I := 0;'#10'  for var K := 0 to 3 do'#10'    Ausgeben(K);'#10 +
    '  with Zeilen do'#10'    for I := 0 to Count - 1 do'#10'      Ausgeben(I);'#10));
  TRuleAssert.Silent(TForVariableMisuseRule.Create,
    'unit Zeilen;'#10'interface'#10'implementation'#10'procedure Lesen(N: Integer);'#10'begin'#10 +
    '  for N := 0 to 3 do'#10'    Ausgeben(N);'#10'  for Unbekannt := 0 to 3 do'#10'    Ausgeben(Unbekannt);'#10 +
    'end;'#10'end.');
end;

procedure TForVariableMisuseTests.OffAndExclude;
const
  cStatements = '  for I := 0 to 9 do'#10'    I := 3;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForVariableMisuseRule.Create, Zeilen(cStatements),
    '{"rules": {"for-variable-misuse": "off"}}', 'Zeilen.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForVariableMisuseRule.Create, Zeilen(cStatements),
    '{"rules": {"group:compiler": "off"}}', 'Zeilen.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForVariableMisuseRule.Create, Zeilen(cStatements),
    '{"rules": {"for-variable-misuse": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Zeilen.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TForVariableMisuseRule.Create, Zeilen(cStatements),
    '{"rules": {"for-variable-misuse": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Zeilen.pas'))));
end;

procedure TForVariableMisuseTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cForVariableMisuseRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

{ TForVariableAfterLoopTests }

procedure TForVariableAfterLoopTests.IssueExampleWithWhileFix;
const
  cStatements = '  for I := 0 to Zeilen.Count - 1 do'#10'    if Zeilen[I] = '''' then'#10'      Break;'#10 +
    '  J := I;'#10;
  cFixed = '  I := 0;'#10'  while I <= Zeilen.Count - 1 do'#10'  begin'#10'    if Zeilen[I] = '''' then'#10 +
    '      Break;'#10'    Inc(I);'#10'  end;'#10'  J := I;'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForVariableAfterLoopRule.Create, Zeilen(cStatements));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cForVariableAfterLoopRuleId, mFindings[0].RuleId);
  Assert.AreEqual('I ist nach der Schleife undefiniert, wenn kein Break erreicht wurde (wie W1037).',
    mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(21, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(8, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Auf while-Schleife umstellen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(Zeilen(cFixed), TChangeSignature.ApplyEdits(Zeilen(cStatements), mFindings[0].Fixes[0].Edits));
end;

procedure TForVariableAfterLoopTests.LaterReadAndCondition;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Gelesen erst nach anderen Anweisungen, in einer Bedingung; je Lesestelle nur die erste.
  mFindings := TRuleAssert.Findings(TForVariableAfterLoopRule.Create,
    Zeilen('  for I := 0 to 9 do'#10'    Ausgeben(I);'#10'  J := 3;'#10'  if I > J then'#10'    Ausgeben(I);'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(21, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Character);
  // downto, Lesen in einem Index.
  mFindings := TRuleAssert.Findings(TForVariableAfterLoopRule.Create,
    Zeilen('  for I := 9 downto 0 do'#10'    if Zeilen[I] = '''' then'#10'      Break;'#10'  J := Length(Zeilen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(21, mFindings[0].Range.StartPos.Line);
end;

procedure TForVariableAfterLoopTests.SilentCases;
begin
  // Zuweisung vor dem Lesen, neue Schleife mit derselben Variable, for var, Feld, Lesen nur im Rumpf,
  // Verlassen der Routine aus dem Rumpf, globale Variable.
  TRuleAssert.Silent(TForVariableAfterLoopRule.Create,
    Zeilen('  for I := 0 to 9 do'#10'    Ausgeben(I);'#10'  I := 0;'#10'  J := I;'#10 +
    '  for I := 0 to 3 do'#10'    Ausgeben(I);'#10'  for I := 0 to 5 do'#10'    Ausgeben(I);'#10 +
    '  for var K := 0 to 3 do'#10'    Ausgeben(K);'#10'  for FIndex := 0 to 3 do'#10'    Ausgeben(FIndex);'#10 +
    '  J := FIndex;'#10'  for GZaehler := 0 to 3 do'#10'    Ausgeben(GZaehler);'#10'  J := GZaehler;'#10));
  TRuleAssert.Silent(TForVariableAfterLoopRule.Create,
    Zeilen('  for I := 0 to Zeilen.Count - 1 do'#10'    if Zeilen[I] = '''' then'#10'    begin'#10 +
    '      Ausgeben(I);'#10'      Exit;'#10'    end;'#10'  Ausgeben(0);'#10));
  // Als Argument einer unbekannten Routine (könnte ein out-Parameter sein) und ohne Schleife.
  TRuleAssert.Silent(TForVariableAfterLoopRule.Create,
    Zeilen('  for I := 0 to 9 do'#10'    Ausgeben(I);'#10'  Ausgeben(I);'#10));
  TRuleAssert.Silent(TForVariableAfterLoopRule.Create, Zeilen('  J := I;'#10));
  // Rumpf ist ein repeat: Das Lesen steht in der Schleife, nicht danach.
  TRuleAssert.Silent(TForVariableAfterLoopRule.Create,
    Zeilen('  for I := 0 to 1 do'#10'    repeat'#10'      if I = 1 then'#10'        J := 2;'#10 +
    '    until J > 0;'#10));
end;

procedure TForVariableAfterLoopTests.OffAndExclude;
const
  cStatements = '  for I := 0 to 9 do'#10'    Ausgeben(I);'#10'  J := I;'#10;
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TForVariableAfterLoopRule.Create, Zeilen(cStatements)))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForVariableAfterLoopRule.Create, Zeilen(cStatements),
    '{"rules": {"for-variable-after-loop": "off"}}', 'Zeilen.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForVariableAfterLoopRule.Create, Zeilen(cStatements),
    '{"rules": {"group:compiler": "off"}}', 'Zeilen.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForVariableAfterLoopRule.Create, Zeilen(cStatements),
    '{"rules": {"for-variable-after-loop": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Zeilen.pas'))));
end;

procedure TForVariableAfterLoopTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cForVariableAfterLoopRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TForVariableMisuseTests);
  TDUnitX.RegisterTestFixture(TForVariableAfterLoopTests);

end.
