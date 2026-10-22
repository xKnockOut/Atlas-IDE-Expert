unit Atlas.Common.Rules.Builtin.Conditions.Tests;

// Tests der Regel constant-condition (#1041): Beispiel aus dem Issue mit
// Korrektur, Konstante der Datei mit Entfernen der Anweisung, else-Zweig,
// gewollte Endlosschleifen, stille Fälle (Variablen, typisierte Konstanten,
// {$IFDEF}, verdeckte Namen), Option switchConstants samt Typprüfung in atlas.json, Abschalten und Ausnahmen.
// infinite-loop (#1042): Beispiel aus dem Issue, repeat mit Sprung zum Kopf,
// Ausgänge (Break, Exit, raise, Halt, Routine der Datei mit raise, Terminated),
// try-Teil eines try … except, Break nur in innerer Schleife bzw. Exit nur in
// anonymer Methode, Abschalten.
// loop-condition-unchanged (#1043): Beispiel aus dem Issue, eine Variable,
// repeat, Änderungen (Inc, Zuweisung, Argument, Methode, X[…]), stille Fälle
// (Aufruf, Feld, var-Parameter, Ausgang, Warteschleife, anonyme Methode,
// lokale Routine, nur X.Eigenschaft), Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConstantConditionTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure FileConstantRemovesStatement;
    [Test]
    procedure FalseWithElseKeepsElse;
    [Test]
    procedure LoopsAndComparisons;
    [Test]
    procedure SilentCases;
    [Test]
    procedure SwitchConstantsOption;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TInfiniteLoopTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure RepeatJumpsToHead;
    [Test]
    procedure ExitsAreSilent;
    [Test]
    procedure InnerBreakDoesNotCount;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TLoopConditionUnchangedTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure SingleVariableAndRepeat;
    [Test]
    procedure ChangesAreSilent;
    [Test]
    procedure UnknownConditionsAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Conditions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Body(const AStatements: string): string;
begin
  Result := 'unit Daten;'#10'interface'#10'implementation'#10'const'#10'  DEBUG_MODUS = False;'#10 +
    '  MAX_ANZAHL = 10;'#10'  Typisiert: Boolean = False;'#10'procedure Laden(Anzahl: Integer);'#10 +
    'begin'#10 + AStatements + 'end;'#10'end.';
end;

function Findings(const ASource: string; const AConfig: string = ''; const APath: string = ''): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TConstantConditionRule.Create, ASource, AConfig, APath);
end;

{ TConstantConditionTests }

procedure TConstantConditionTests.IssueExampleWithFix;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Body('  if (Anzahl > 0) or True then'#10'    Verarbeiten;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(ConstantConditionRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual('Die Bedingung ist immer wahr (… or True).', Found[0].Message);
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
  Assert.AreEqual(5, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Bedingung entfernen', Found[0].Fixes[0].Title);
  Assert.AreEqual(Body('  Verarbeiten;'#10), TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits));
end;

procedure TConstantConditionTests.FileConstantRemovesStatement;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Body('  Start;'#10'  if DEBUG_MODUS then'#10'    Protokoll(''Laden'');'#10'  Ende;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Bedingung ist immer falsch (DEBUG_MODUS = False).', Found[0].Message);
  Assert.AreEqual('Toten Zweig entfernen', Found[0].Fixes[0].Title);
  Assert.AreEqual(Body('  Start;'#10'  Ende;'#10), TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits));
  // Vergleich mit einer Zahlkonstanten und not.
  Found := Findings(Body('  if MAX_ANZAHL > 20 then'#10'    Exit;'#10'  if not DEBUG_MODUS and (Anzahl > 0) then'#10 +
    '    Exit;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Bedingung ist immer falsch (MAX_ANZAHL > 20).', Found[0].Message);
end;

procedure TConstantConditionTests.FalseWithElseKeepsElse;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Body('  if False then'#10'    Alt'#10'  else'#10'  begin'#10'    Neu;'#10'    Fertig;'#10'  end;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Bedingung ist immer falsch (False).', Found[0].Message);
  Assert.AreEqual(Body('  begin'#10'    Neu;'#10'    Fertig;'#10'  end;'#10),
    TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits));
  // Teil mit and: False and X ist immer falsch.
  Found := Findings(Body('  if False and (Anzahl > 0) then'#10'    Exit;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Bedingung ist immer falsch (False and …).', Found[0].Message);
end;

procedure TConstantConditionTests.LoopsAndComparisons;
var
  Found: TArray<TRuleFinding>;
begin
  // Gewollte Endlosschleifen bleiben still.
  Assert.AreEqual(0, Integer(Length(Findings(Body('  while True do'#10'    Break;'#10 +
    '  repeat'#10'    Break;'#10'  until False;'#10)))));
  Found := Findings(Body('  while DEBUG_MODUS do'#10'    Inc(Anzahl);'#10'  repeat'#10'    Inc(Anzahl);'#10 +
    '  until 1 = 1;'#10));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Die Bedingung ist immer falsch (DEBUG_MODUS = False).', Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)), 'Schleifen ohne Korrektur');
  Assert.AreEqual('Die Bedingung ist immer wahr (1 = 1).', Found[1].Message);
end;

procedure TConstantConditionTests.SilentCases;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Body('  if Anzahl > 0 then'#10'    Exit;'#10 +
    '  if Typisiert then'#10'    Exit;'#10'  if Anzahl > MAX_ANZAHL then'#10'    Exit;'#10 +
    '  if Unbekannt or DEBUG_MODUS then'#10'    Exit;'#10)))), 'Variablen');
  // Konstante in einem Zweig von {$IFDEF}.
  Assert.AreEqual(0, Integer(Length(Findings('unit Daten;'#10'interface'#10'implementation'#10'const'#10 +
    '{$IFDEF DEBUG}'#10'  Ausgabe = True;'#10'{$ELSE}'#10'  Ausgabe = False;'#10'{$ENDIF}'#10 +
    'procedure Laden;'#10'begin'#10'  if Ausgabe then'#10'    Protokoll;'#10'end;'#10'end.'))), 'IFDEF');
  // Bedingung mit Direktive darin.
  Assert.AreEqual(0, Integer(Length(Findings(Body('  if {$IFDEF DEBUG} True {$ELSE} False {$ENDIF} then'#10 +
    '    Exit;'#10)))), 'Direktive');
  // Lokale Variable verdeckt die Konstante.
  Assert.AreEqual(0, Integer(Length(Findings(Body('  if DEBUG_MODUS then'#10'    Exit;'#10).Replace(
    'begin'#10, 'var'#10'  DEBUG_MODUS: Boolean;'#10'begin'#10)))), 'verdeckt');
end;

procedure TConstantConditionTests.SwitchConstantsOption;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Body('  if DEBUG_MODUS then'#10'    Protokoll;'#10);
  Assert.AreEqual(1, Integer(Length(Findings(Source))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"constant-condition": {"switchConstants": ["debug_modus"]}}}'))));
  // Literale bleiben gemeldet.
  Assert.AreEqual(1, Integer(Length(Findings(Body('  if False then'#10'    Protokoll;'#10),
    '{"rules": {"constant-condition": {"switchConstants": ["DEBUG_MODUS"]}}}'))));
  TConfigurationParser.Parse('{"rules": {"constant-condition": {"switchConstants": "DEBUG_MODUS"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"switchConstants" muss eine Liste von Texten sein', Issues[0].Message);
  TConfigurationParser.Parse('{"rules": {"constant-condition": {"switchConstants": ["DEBUG_MODUS"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TConstantConditionTests.OffAndExclude;
var
  Source: string;
begin
  Source := Body('  if False then'#10'    Protokoll;'#10);
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"constant-condition": "off"}}',
    'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:find-bugs": "off"}}',
    'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"constant-condition": {"exclude": ["Source/*.pas"]}}}', 'Source/Daten.pas'))));
end;

{ TInfiniteLoopTests }

function LoopFindings(const ASource: string; const AConfig: string = ''; const APath: string = ''):
  TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TInfiniteLoopRule.Create, ASource, AConfig, APath);
end;

function Lesen(const AStatements: string): string;
begin
  Result := 'unit Daten;'#10'interface'#10'implementation'#10'procedure Pruefen(const S: string);'#10'begin'#10 +
    '  if S = '''' then'#10'    raise EArgumentException.Create(''leer'');'#10'end;'#10 +
    'procedure Lesen(Leser: TStreamReader);'#10'var'#10'  Zeile: string;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TInfiniteLoopTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := LoopFindings(Lesen('  while True do'#10'  begin'#10'    Zeile := Leser.ReadLine;'#10 +
    '    Verarbeiten(Zeile);'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(InfiniteLoopRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Assert.AreEqual('Die Schleife hat keinen Ausgang (kein Break, Exit oder raise).', Found[0].Message);
  Assert.AreEqual(12, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
  Assert.AreEqual(12, Found[0].Range.EndPos.Line);
  Assert.AreEqual(12, Found[0].Range.EndPos.Character);
end;

procedure TInfiniteLoopTests.RepeatJumpsToHead;
var
  Found: TArray<TRuleFinding>;
begin
  Found := LoopFindings(Lesen('  repeat'#10'    Zeile := Leser.ReadLine;'#10'  until False;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(14, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.IsTrue(Found[0].Fixes[0].HasJump);
  Assert.AreEqual(12, Found[0].Fixes[0].JumpTo.Line);
  Assert.AreEqual(2, Found[0].Fixes[0].JumpTo.Character);
end;

procedure TInfiniteLoopTests.ExitsAreSilent;
const
  Exits: array[0..7] of string = ('if Zeile = '''' then Break;', 'if Zeile = '''' then Exit;',
    'if Zeile = '''' then raise EAbort.Create(''Ende'');', 'if Zeile = '''' then Halt(1);', 'Pruefen(Zeile);',
    'if Zeile = '''' then Abort;', 'if TThread.CurrentThread.CheckTerminated then Exit;',
    'if Zeile = '''' then goto Ende;');
var
  Statement: string;
begin
  for Statement in Exits do
    Assert.AreEqual(0, Integer(Length(LoopFindings(Lesen('  while True do'#10'  begin'#10 +
      '    Zeile := Leser.ReadLine;'#10'    ' + Statement + #10'  end;'#10)))), Statement);
  // Normale Schleifen und Terminated im Thread.
  Assert.AreEqual(0, Integer(Length(LoopFindings(Lesen('  while not Leser.EndOfStream do'#10 +
    '    Zeile := Leser.ReadLine;'#10'  while True do'#10'    if Terminated then'#10'      Zeile := '''';'#10)))));
  // Lesen bis zur Ausnahme im try-Teil eines try … except; im except-Teil zählt das nicht.
  Assert.AreEqual(0, Integer(Length(LoopFindings(Lesen('  try'#10'    while True do'#10 +
    '      Verarbeiten(Leser.ReadLine);'#10'  except'#10'    on EEndOfStream do'#10'      ;'#10'  end;'#10)))));
  Assert.AreEqual(1, Integer(Length(LoopFindings(Lesen('  try'#10'    Zeile := '''';'#10'  except'#10 +
    '    while True do'#10'      Verarbeiten(Leser.ReadLine);'#10'  end;'#10)))));
end;

procedure TInfiniteLoopTests.InnerBreakDoesNotCount;
var
  Found: TArray<TRuleFinding>;
begin
  Found := LoopFindings(Lesen('  while True do'#10'  begin'#10'    for Zeile in Leser.Zeilen do'#10 +
    '      if Zeile = '''' then'#10'        Break;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), 'Break der inneren Schleife');
  Found := LoopFindings(Lesen('  while True do'#10'  begin'#10'    TThread.Queue(nil,'#10 +
    '      procedure'#10'      begin'#10'        Exit;'#10'      end);'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), 'Exit der anonymen Methode');
end;

procedure TInfiniteLoopTests.OffAndExclude;
var
  Source: string;
begin
  Source := Lesen('  while True do'#10'    Zeile := Leser.ReadLine;'#10);
  Assert.AreEqual(1, Integer(Length(LoopFindings(Source, '', 'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(LoopFindings(Source, '{"rules": {"infinite-loop": "off"}}', 'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(LoopFindings(Source, '{"rules": {"group:find-bugs": "off"}}',
    'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(LoopFindings(Source, '{"rules": {"infinite-loop": {"exclude": ["Source/*.pas"]}}}',
    'Source/Daten.pas'))));
end;

{ TLoopConditionUnchangedTests }

function UnchangedFindings(const ASource: string; const AConfig: string = ''; const APath: string = ''):
  TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TLoopConditionUnchangedRule.Create, ASource, AConfig, APath);
end;

function Schleife(const AStatements: string): string;
begin
  Result := 'unit Daten;'#10'interface'#10'type'#10'  TPruefer = class'#10'    FFertig: Boolean;'#10 +
    '    procedure Pruefen(Liste: TStringList; var Fertig: Boolean);'#10'  end;'#10'implementation'#10 +
    'procedure TPruefer.Pruefen(Liste: TStringList; var Fertig: Boolean);'#10'var'#10'  I: Integer;'#10 +
    '  Werte: TArray<Integer>;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TLoopConditionUnchangedTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := UnchangedFindings(Schleife('  I := 0;'#10'  while I < Liste.Count do'#10'  begin'#10 +
    '    Pruefe(Liste[I]);'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(LoopConditionUnchangedRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Found[0].Confidence));
  Assert.AreEqual('I und Liste werden im Rumpf nie verändert; die Schleife endet nicht.', Found[0].Message);
  Assert.AreEqual(14, Found[0].Range.StartPos.Line);
  Assert.AreEqual(8, Found[0].Range.StartPos.Character);
end;

procedure TLoopConditionUnchangedTests.SingleVariableAndRepeat;
var
  Found: TArray<TRuleFinding>;
begin
  Found := UnchangedFindings(Schleife('  repeat'#10'    Pruefe(Liste[0]);'#10'  until I > 10;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('I wird im Rumpf nie verändert; die Schleife endet nicht.', Found[0].Message);
  Assert.AreEqual(15, Found[0].Range.StartPos.Line);
end;

procedure TLoopConditionUnchangedTests.ChangesAreSilent;
const
  Bodies: array[0..7] of string = ('Inc(I);', 'I := I + 1;', 'Lesen(I);', 'Liste.Delete(0);',
    'Pruefe(Liste.Count);', 'for I := 0 to 3 do Pruefe(I);', 'Werte[0] := 0;', 'Dec(Werte[0]);');
var
  Body: string;
begin
  for Body in Bodies do
    Assert.AreEqual(0, Integer(Length(UnchangedFindings(Schleife('  while (I < Liste.Count) and (Werte[0] > 0) do'#10 +
      '    ' + Body + #10)))), Body);
end;

procedure TLoopConditionUnchangedTests.UnknownConditionsAreSilent;
const
  Loops: array[0..9] of string = (
    '  while I < Anzahl(Liste) do'#10'    Pruefe(Liste[I]);'#10,
    '  while not FFertig do'#10'    Pruefe(Liste[I]);'#10,
    '  while not Fertig do'#10'    Pruefe(Liste[I]);'#10,
    '  while I < 10 do'#10'    if Liste[I] = '''' then'#10'      Break;'#10,
    '  while I < 10 do'#10'    Sleep(10);'#10,
    '  while I < 10 do'#10'    TThread.Queue(nil, procedure begin Inc(I); end);'#10,
    '  while Liste.Count > 0 do'#10'    Pruefe(Liste[0]);'#10,
    '  while I < 10 do'#10'    with Liste do'#10'      Pruefe(Text);'#10,
    '  while not Terminated do'#10'    Pruefe(Liste[0]);'#10,
    '  while True do'#10'    Pruefe(Liste[0]);'#10);
var
  Loop: string;
begin
  for Loop in Loops do
    Assert.AreEqual(0, Integer(Length(UnchangedFindings(Schleife(Loop)))), Loop);
  // Lokale Routine kann I ändern.
  Assert.AreEqual(0, Integer(Length(UnchangedFindings(Schleife('  while I < 10 do'#10'    Weiter;'#10).Replace(
    '  Werte: TArray<Integer>;'#10, '  Werte: TArray<Integer>;'#10'  procedure Weiter;'#10'  begin'#10'    Inc(I);'#10 +
    '  end;'#10)))));
end;

procedure TLoopConditionUnchangedTests.OffAndExclude;
var
  Source: string;
begin
  Source := Schleife('  while I < Liste.Count do'#10'    Pruefe(Liste[I]);'#10);
  Assert.AreEqual(1, Integer(Length(UnchangedFindings(Source, '', 'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(UnchangedFindings(Source, '{"rules": {"loop-condition-unchanged": "off"}}',
    'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(UnchangedFindings(Source, '{"rules": {"group:find-bugs": "off"}}',
    'Source/Daten.pas'))));
  Assert.AreEqual(0, Integer(Length(UnchangedFindings(Source,
    '{"rules": {"loop-condition-unchanged": {"exclude": ["Source/*.pas"]}}}', 'Source/Daten.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TConstantConditionTests);
  TDUnitX.RegisterTestFixture(TInfiniteLoopTests);
  TDUnitX.RegisterTestFixture(TLoopConditionUnchangedTests);

end.
