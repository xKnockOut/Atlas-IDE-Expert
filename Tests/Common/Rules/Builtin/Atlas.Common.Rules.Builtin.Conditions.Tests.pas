unit Atlas.Common.Rules.Builtin.Conditions.Tests;

// Tests der Regel constant-condition (#1041): Beispiel aus dem Issue mit
// Korrektur, Konstante der Datei mit Entfernen der Anweisung, else-Zweig,
// gewollte Endlosschleifen, stille Fälle (Variablen, typisierte Konstanten,
// {$IFDEF}, verdeckte Namen), Option switchConstants samt Typprüfung in atlas.json, Abschalten und Ausnahmen.

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

initialization
  TDUnitX.RegisterTestFixture(TConstantConditionTests);

end.
