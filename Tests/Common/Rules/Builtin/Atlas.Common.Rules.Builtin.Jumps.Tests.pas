unit Atlas.Common.Rules.Builtin.Jumps.Tests;

// Tests der Regel jump-outside-allowed-scope (#984): Beispiel aus dem Issue mit
// Korrektur, Continue ohne Korrektur, Break/Continue/Exit im finally, Schleife
// im finally, anonyme Methode in der Schleife, stille Fälle (Schleifen,
// TMonitor.Exit, eigene Routine Break, Parserfehler), Abschalten, Gruppe und
// Ausnahmen. label-misuse (#995): Beispiel aus dem Issue, goto in einen try-Block
// und zwischen try und except, doppelte, nicht deklarierte und nie gesetzte
// Marken, lokale Prozeduren, stille Fälle (Ziffernmarken, exklusive Zweige,
// asm, goto im except), Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJumpOutsideAllowedScopeTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ContinueOutsideLoop;
    [Test]
    procedure JumpsOutOfFinally;
    [Test]
    procedure AnonymousMethodStartsNewScope;
    [Test]
    procedure AllowedJumpsAreSilent;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure RuleIsRegistered;
  end;

  [TestFixture]
  TLabelMisuseTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure IntoTryAndBetweenParts;
    [Test]
    procedure DuplicateUndeclaredAndNotSet;
    [Test]
    procedure NestedRoutinesHaveOwnLabels;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Jumps,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Suche(const AStatements: string): string;
begin
  Result := 'unit Suchen;'#10'interface'#10'implementation'#10 +
    'procedure TSuche.Pruefen(const Eintrag: TEintrag);'#10'var'#10'  I: Integer;'#10'begin'#10 +
    AStatements + 'end;'#10'end.';
end;

{ TJumpOutsideAllowedScopeTests }

procedure TJumpOutsideAllowedScopeTests.IssueExampleWithFix;
const
  Statements = '  if Eintrag.Treffer then'#10'    Break;'#10'  Merken(Eintrag);'#10;
  Fixed = '  if Eintrag.Treffer then'#10'    Exit;'#10'  Merken(Eintrag);'#10;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create, Suche(Statements));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(JumpOutsideAllowedScopeRuleId, Findings[0].RuleId);
  Assert.AreEqual('Break außerhalb einer Schleife (wie E2097).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(9, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Break durch Exit ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Text := TChangeSignature.ApplyEdits(Suche(Statements), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Suche(Fixed), Text);
  TRuleAssert.Silent(TJumpOutsideAllowedScopeRule.Create, Text);
end;

procedure TJumpOutsideAllowedScopeTests.ContinueOutsideLoop;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create,
    Suche('  if not Eintrag.Treffer then'#10'    continue;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('continue außerhalb einer Schleife (wie E2097).', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'Exit wäre bei Continue keine sinngleiche Korrektur');
end;

procedure TJumpOutsideAllowedScopeTests.JumpsOutOfFinally;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create,
    Suche('  for I := 0 to 9 do'#10'    try'#10'      Merken(Eintrag);'#10'    finally'#10 +
    '      if I = 5 then'#10'        Break;'#10'      Continue;'#10'      Exit;'#10'    end;'#10 +
    '  try'#10'  finally'#10'    try'#10'    except'#10'      Exit;'#10'    end;'#10'  end;'#10));
  Assert.AreEqual(4, Integer(Length(Findings)));
  Assert.AreEqual('Break darf einen finally-Block nicht verlassen (wie E2126).', Findings[0].Message);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Continue darf einen finally-Block nicht verlassen (wie E2126).', Findings[1].Message);
  Assert.AreEqual('Exit darf einen finally-Block nicht verlassen (wie E2126).', Findings[2].Message);
  Assert.AreEqual('Exit darf einen finally-Block nicht verlassen (wie E2126).', Findings[3].Message);
  Assert.AreEqual(20, Findings[3].Range.StartPos.Line);
  // Break außerhalb einer Schleife im finally: keine Korrektur nach Exit, das wäre wieder E2126.
  Findings := TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create,
    Suche('  try'#10'  finally'#10'    Break;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Break außerhalb einer Schleife (wie E2097).', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TJumpOutsideAllowedScopeTests.AnonymousMethodStartsNewScope;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create,
    Suche('  for I := 0 to 9 do'#10'    Liste.ForEach('#10'      procedure(const S: string)'#10'      begin'#10 +
    '        if S = '''' then'#10'          Break;'#10'      end);'#10 +
    '  try'#10'  finally'#10'    Ausfuehren(procedure begin Exit; end);'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)), 'Exit in der anonymen Methode verlässt das finally nicht');
  Assert.AreEqual('Break außerhalb einer Schleife (wie E2097).', Findings[0].Message);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Line);
end;

procedure TJumpOutsideAllowedScopeTests.AllowedJumpsAreSilent;
begin
  // Schleifen aller Art, Schleife im finally, except, case und with in der Schleife, Exit außerhalb von finally.
  TRuleAssert.Silent(TJumpOutsideAllowedScopeRule.Create,
    Suche('  for I := 0 to 9 do'#10'    if I = 3 then Break else Continue;'#10 +
    '  for var S in Liste do'#10'    case Length(S) of'#10'      0: Continue;'#10'    end;'#10 +
    '  while Eintrag.Weiter do'#10'    with Eintrag do'#10'      Break;'#10 +
    '  repeat'#10'    try'#10'      Break;'#10'    except'#10'      Continue;'#10'    end;'#10'  until False;'#10 +
    '  try'#10'    Exit;'#10'  finally'#10'    for I := 0 to 3 do'#10'      if I = 2 then Break;'#10'  end;'#10 +
    '  TMonitor.Exit(FLock);'#10'  Exit(1);'#10));
  // Eigene Routine namens Break und Parserfehler in der Routine.
  TRuleAssert.Silent(TJumpOutsideAllowedScopeRule.Create,
    'unit Suchen;'#10'interface'#10'implementation'#10'procedure Break;'#10'begin'#10'end;'#10 +
    'procedure Pruefen;'#10'begin'#10'  Break;'#10'end;'#10'end.');
  TRuleAssert.Silent(TJumpOutsideAllowedScopeRule.Create, Suche('  if then'#10'    Break;'#10));
end;

procedure TJumpOutsideAllowedScopeTests.OffAndExclude;
const
  Statements = '  Break;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create, Suche(Statements),
    '{"rules": {"jump-outside-allowed-scope": "off"}}', 'Suchen.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create, Suche(Statements),
    '{"rules": {"group:compiler": "off"}}', 'Suchen.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create, Suche(Statements),
    '{"rules": {"jump-outside-allowed-scope": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Suchen.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TJumpOutsideAllowedScopeRule.Create, Suche(Statements),
    '{"rules": {"jump-outside-allowed-scope": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Suchen.pas'))));
end;

procedure TJumpOutsideAllowedScopeTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = JumpOutsideAllowedScopeRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

{ TLabelMisuseTests }

function Ablauf(const ALabels, AStatements: string): string;
begin
  Result := 'unit Ablaeufe;'#10'interface'#10'implementation'#10'procedure TAblauf.Ausfuehren(Fertig: Boolean);'#10 +
    ALabels + 'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TLabelMisuseTests.IssueExample;
const
  Statements = '  try'#10'    if Fertig then goto Weiter;'#10'  finally'#10'    Aufraeumen;'#10'  end;'#10 +
    'Weiter:'#10'  Melden;'#10;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLabelMisuseRule.Create, Ablauf('label Weiter;'#10, Statements));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(LabelMisuseRuleId, Findings[0].RuleId);
  Assert.AreEqual('goto Weiter verlässt einen try-Block (wie E2127).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(19, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(30, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Die Marke im selben Block: still.
  TRuleAssert.Silent(TLabelMisuseRule.Create, Ablauf('label Weiter;'#10,
    '  try'#10'    if Fertig then goto Weiter;'#10'    Lesen;'#10'  Weiter:'#10'    Melden;'#10'  finally'#10 +
    '    Aufraeumen;'#10'  end;'#10));
end;

procedure TLabelMisuseTests.IntoTryAndBetweenParts;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLabelMisuseRule.Create, Ablauf('label Innen, Handler;'#10,
    '  if Fertig then goto Innen;'#10'  try'#10'  Innen:'#10'    Lesen;'#10'    goto Handler;'#10'  except'#10 +
    '  Handler:'#10'    Melden;'#10'  end;'#10));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('goto Innen springt in einen try-Block (wie E2127).', Findings[0].Message);
  Assert.AreEqual('goto Handler springt in einen except-Block (wie E2127).', Findings[1].Message);
end;

procedure TLabelMisuseTests.DuplicateUndeclaredAndNotSet;
var
  Findings: TArray<TRuleFinding>;
begin
  // E2073 doppelt gesetzt, E2093 nicht deklariert (gesetzt und angesprungen), E2074 nie gesetzt. goto Anders
  // (nirgends deklariert, nie gesetzt) meldet die Syntaxprüfung als E2031, die Regel schweigt dazu.
  Findings := TRuleAssert.Findings(TLabelMisuseRule.Create, Ablauf('label Doppelt, Fehlt;'#10,
    'Doppelt:'#10'  Lesen;'#10'Doppelt:'#10'  Melden;'#10'Fremd:'#10'  goto Fremd;'#10'  goto Anders;'#10 +
    '  goto Fehlt;'#10));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Marke Fehlt wird angesprungen, aber nie gesetzt (wie E2074).', Findings[0].Message);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(15, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('Marke Doppelt ist bereits gesetzt (wie E2073).', Findings[1].Message);
  Assert.AreEqual(8, Findings[1].Range.StartPos.Line);
  Assert.AreEqual('Marke Fremd ist in dieser Routine nicht deklariert (wie E2093).', Findings[2].Message);
  Assert.AreEqual(10, Findings[2].Range.StartPos.Line);
end;

procedure TLabelMisuseTests.NestedRoutinesHaveOwnLabels;
var
  Findings: TArray<TRuleFinding>;
begin
  // Die Marke der äußeren Routine ist in der lokalen Prozedur nicht deklariert.
  Findings := TRuleAssert.Findings(TLabelMisuseRule.Create,
    'unit Ablaeufe;'#10'interface'#10'implementation'#10'procedure TAblauf.Ausfuehren;'#10'label Ende;'#10 +
    '  procedure Abbrechen;'#10'  begin'#10'    goto Ende;'#10'  end;'#10'begin'#10'  Abbrechen;'#10'Ende:'#10 +
    'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Marke Ende ist in dieser Routine nicht deklariert (wie E2093).', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
end;

procedure TLabelMisuseTests.SilentCases;
begin
  // Richtige Verwendung, Ziffernmarken (007 = 7), Marke in exklusiven Zweigen, asm, goto innerhalb des except.
  TRuleAssert.Silent(TLabelMisuseRule.Create, Ablauf('label Nochmal, 7;'#10,
    'Nochmal:'#10'  if not Fertig then goto Nochmal;'#10'  goto 007;'#10'  Lesen;'#10'7:'#10'  Melden;'#10));
  TRuleAssert.Silent(TLabelMisuseRule.Create, Ablauf('label Ende;'#10,
    '  if Fertig then goto Ende;'#10'{$IFDEF WIN64}'#10'Ende:'#10'  Lesen;'#10'{$ELSE}'#10'Ende:'#10 +
    '  Melden;'#10'{$ENDIF}'#10));
  TRuleAssert.Silent(TLabelMisuseRule.Create, Ablauf('label Ende;'#10,
    '  goto Ende;'#10'  asm'#10'  Ende:'#10'    nop'#10'  end;'#10));
  TRuleAssert.Silent(TLabelMisuseRule.Create, Ablauf('label Nochmal;'#10,
    '  try'#10'    Lesen;'#10'  except'#10'  Nochmal:'#10'    if not Fertig then goto Nochmal;'#10'  end;'#10));
  TRuleAssert.Silent(TLabelMisuseRule.Create, Ablauf('', '  Lesen;'#10'  Melden;'#10));
end;

procedure TLabelMisuseTests.OffAndExclude;
const
  // Deklariert und angesprungen, aber nie gesetzt (E2074).
  Labels = 'label Weiter;'#10;
  Statements = '  goto Weiter;'#10;
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLabelMisuseRule.Create, Ablauf(Labels, Statements)))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLabelMisuseRule.Create, Ablauf(Labels, Statements),
    '{"rules": {"label-misuse": "off"}}', 'Ablaeufe.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLabelMisuseRule.Create, Ablauf(Labels, Statements),
    '{"rules": {"group:compiler": "off"}}', 'Ablaeufe.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLabelMisuseRule.Create, Ablauf(Labels, Statements),
    '{"rules": {"label-misuse": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Ablaeufe.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TJumpOutsideAllowedScopeTests);
  TDUnitX.RegisterTestFixture(TLabelMisuseTests);

end.
