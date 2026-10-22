unit Atlas.Common.Rules.Builtin.TypedExpressions.Tests;

// Tests der Regeln mit Ausdruckstypen (Gruppe „Compiler vorab“):
// comparison-always-constant (#1011): Beispiel aus dem Issue, immer falsche
// und gespiegelte Vergleiche, benannte Konstanten, Felder aus dem Index,
// case-Marken außerhalb des Bereichs, bedingte Deklarationen, stille Fälle,
// Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TComparisonAlwaysConstantTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure AlwaysFalseAndMirrored;
    [Test]
    procedure NamedConstantsAndIndexMembers;
    [Test]
    procedure CaseLabelsOutsideRange;
    [Test]
    procedure ConditionalDeclarationIsSilent;
    [Test]
    procedure PossibleComparisonsAreSilent;
    [Test]
    procedure OutcomeTable;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.TypedExpressions,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

/// <summary>Routine Pruefen mit den Deklarationen ADecls (var-Abschnitt) und den Anweisungen ABody.</summary>
function Routine(const ADecls, ABody: string): string;
begin
  Result := 'unit Zaehler;'#10'interface'#10'implementation'#10'procedure Pruefen;'#10'var'#10 + ADecls +
    'begin'#10 + ABody + 'end;'#10'end.';
end;

function ComparisonFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TComparisonAlwaysConstantRule.Create, ASource);
end;

function ComparisonFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TComparisonAlwaysConstantRule.Create, ASource, AConfig, APath);
end;

function KontoIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Konten;'#10'interface'#10'const'#10'  MaxStufe = 255;'#10 +
    'type'#10'  TKonto = class'#10'  private'#10'    FSaldo: Cardinal;'#10'  public'#10 +
    '    function Stufe: Byte;'#10'    property Saldo: Cardinal read FSaldo;'#10'  end;'#10'implementation'#10 +
    'function TKonto.Stufe: Byte;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.', 'C:\Projekt\Konten.pas', nil));
end;

{ TComparisonAlwaysConstantTests }

procedure TComparisonAlwaysConstantTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ComparisonFindings(Routine('  Rest: Cardinal;'#10, '  while Rest >= 0 do'#10'    Dec(Rest);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(ComparisonAlwaysConstantRuleId, Found[0].RuleId);
  Assert.AreEqual('Rest ist Cardinal; Rest >= 0 ist immer wahr, die Schleife endet nie (wie W1022).',
    Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(8, Found[0].Range.StartPos.Character);
  Assert.AreEqual(17, Found[0].Range.EndPos.Character);
  // Korrigiert: Rest > 0.
  Assert.AreEqual(0, Integer(Length(ComparisonFindings(Routine('  Rest: Cardinal;'#10,
    '  while Rest > 0 do'#10'    Dec(Rest);'#10)))));
end;

procedure TComparisonAlwaysConstantTests.AlwaysFalseAndMirrored;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ComparisonFindings(Routine('  B: Byte;'#10'  W: Word;'#10,
    '  if B > 255 then'#10'    Exit;'#10'  if 256 <= B then'#10'    Exit;'#10'  if B < 0 then'#10'    Exit;'#10 +
    '  if B = 300 then'#10'    Exit;'#10'  if B <> -1 then'#10'    Exit;'#10'  if (W) < 65536 then'#10'    Exit;'#10 +
    '  repeat'#10'    Inc(B);'#10'  until B > 255;'#10'  while B < 0 do'#10'    Inc(B);'#10));
  Assert.AreEqual(8, Integer(Length(Found)));
  Assert.AreEqual('B ist Byte; B > 255 ist immer falsch (wie W1021).', Found[0].Message);
  Assert.AreEqual('B ist Byte; 256 <= B ist immer falsch (wie W1021).', Found[1].Message);
  Assert.AreEqual('B ist Byte; B < 0 ist immer falsch (wie W1021).', Found[2].Message);
  Assert.AreEqual('B ist Byte; B = 300 ist immer falsch (wie W1021).', Found[3].Message);
  Assert.AreEqual('B ist Byte; B <> -1 ist immer wahr (wie W1022).', Found[4].Message);
  Assert.AreEqual('W ist Word; (W) < 65536 ist immer wahr (wie W1022).', Found[5].Message);
  Assert.AreEqual('B ist Byte; B > 255 ist immer falsch, die Schleife endet nie (wie W1021).', Found[6].Message);
  Assert.AreEqual('B ist Byte; B < 0 ist immer falsch, die Schleife läuft nie (wie W1021).', Found[7].Message);
end;

procedure TComparisonAlwaysConstantTests.NamedConstantsAndIndexMembers;
var
  Found: TArray<TRuleFinding>;
begin
  Found := TRuleAssert.IndexFindings(TComparisonAlwaysConstantRule.Create, 'unit Pruefung;'#10'interface'#10 +
    'uses'#10'  Konten;'#10'implementation'#10'const'#10'  Unten = -1;'#10 +
    'procedure Pruefen(Konto: TKonto);'#10'begin'#10'  if Konto.Saldo < 0 then'#10'    Exit;'#10 +
    '  if Konto.Stufe > MaxStufe then'#10'    Exit;'#10'  if Konto.Saldo > Unten then'#10'    Exit;'#10 +
    '  if Konto.Saldo > 0 then'#10'    Exit;'#10'end;'#10'end.', KontoIndex, '', 'Pruefung.pas');
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Konto.Saldo ist Cardinal; Konto.Saldo < 0 ist immer falsch (wie W1021).', Found[0].Message);
  Assert.AreEqual('Konto.Stufe ist Byte; Konto.Stufe > MaxStufe ist immer falsch (wie W1021).', Found[1].Message);
  Assert.AreEqual('Konto.Saldo ist Cardinal; Konto.Saldo > Unten ist immer wahr (wie W1022).', Found[2].Message);
end;

procedure TComparisonAlwaysConstantTests.CaseLabelsOutsideRange;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ComparisonFindings(Routine('  B: Byte;'#10,
    '  case B of'#10'    1, 300:'#10'      Exit;'#10'    250..400:'#10'      Exit;'#10'    256..300:'#10 +
    '      Exit;'#10'    -5..-1:'#10'      Exit;'#10'  end;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('300 liegt außerhalb des Bereichs von Byte; der Zweig wird nie ausgeführt (wie W1018).',
    Found[0].Message);
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual('256..300 liegt außerhalb des Bereichs von Byte; der Zweig wird nie ausgeführt (wie W1018).',
    Found[1].Message);
  Assert.AreEqual('-5..-1 liegt außerhalb des Bereichs von Byte; der Zweig wird nie ausgeführt (wie W1018).',
    Found[2].Message);
  // Integer: alle Marken im Bereich.
  Assert.AreEqual(0, Integer(Length(ComparisonFindings(Routine('  I: Integer;'#10,
    '  case I of'#10'    -5..300:'#10'      Exit;'#10'  end;'#10)))));
end;

procedure TComparisonAlwaysConstantTests.ConditionalDeclarationIsSilent;
var
  Found: TArray<TRuleFinding>;
begin
  // Unter X ist Rest ein Integer: dcc warnt dann nicht.
  Found := ComparisonFindings(Routine('{$IFDEF X}'#10'  Rest: Integer;'#10'{$ELSE}'#10'  Rest: Cardinal;'#10 +
    '{$ENDIF}'#10, '  if Rest >= 0 then'#10'    Exit;'#10));
  Assert.AreEqual(0, Integer(Length(Found)));
  // Zwei getrennte {$IFDEF X}: Die Zweige gelten als verschieden, also still.
  Found := ComparisonFindings(Routine('{$IFDEF X}'#10'  Rest: Cardinal;'#10'{$ENDIF}'#10,
    '{$IFDEF X}'#10'  if Rest >= 0 then'#10'    Exit;'#10'{$ENDIF}'#10));
  Assert.AreEqual(0, Integer(Length(Found)));
  // Die ganze Routine im selben Zweig: gemeldet.
  Found := ComparisonFindings('unit Zaehler;'#10'interface'#10'implementation'#10'{$IFDEF X}'#10 +
    'procedure Pruefen;'#10'var'#10'  Rest: Cardinal;'#10'begin'#10'  if Rest >= 0 then'#10'    Exit;'#10'end;'#10 +
    '{$ENDIF}'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
end;

procedure TComparisonAlwaysConstantTests.PossibleComparisonsAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(ComparisonFindings(Routine(
    '  I: Integer;'#10'  C: Cardinal;'#10'  B: Byte;'#10'  N: NativeInt;'#10'  L: LongInt;'#10'  S: string;'#10 +
    '  Stufe: 1..5;'#10'  Unbekannt: TUnbekannt;'#10'  D: Double;'#10,
    '  if I >= 0 then'#10'    Exit;'#10'  if C > 0 then'#10'    Exit;'#10'  if B < 255 then'#10'    Exit;'#10 +
    '  if B <= 254 then'#10'    Exit;'#10'  if N < 2147483648 then'#10'    Exit;'#10 +
    '  if L > 2147483647 then'#10'    Exit;'#10'  if Length(S) < 0 then'#10'    Exit;'#10 +
    '  if C - 1 >= 0 then'#10'    Exit;'#10'  if Stufe > 5 then'#10'    Exit;'#10 +
    '  if Unbekannt >= 0 then'#10'    Exit;'#10'  if D >= 0 then'#10'    Exit;'#10'  if C >= I then'#10'    Exit;'#10 +
    '  if 1 > 2 then'#10'    Exit;'#10)))));
end;

procedure TComparisonAlwaysConstantTests.OutcomeTable;
begin
  Assert.AreEqual(1, TComparisonAlwaysConstantRule.Outcome('>=', 0, 0, 255));
  Assert.AreEqual(-1, TComparisonAlwaysConstantRule.Outcome('>=', 1, 0, 255));
  Assert.AreEqual(0, TComparisonAlwaysConstantRule.Outcome('>=', 256, 0, 255));
  Assert.AreEqual(1, TComparisonAlwaysConstantRule.Outcome('<=', 255, 0, 255));
  Assert.AreEqual(0, TComparisonAlwaysConstantRule.Outcome('<=', -1, 0, 255));
  Assert.AreEqual(-1, TComparisonAlwaysConstantRule.Outcome('<=', 254, 0, 255));
  Assert.AreEqual(1, TComparisonAlwaysConstantRule.Outcome('<', 256, 0, 255));
  Assert.AreEqual(0, TComparisonAlwaysConstantRule.Outcome('<', 0, 0, 255));
  Assert.AreEqual(1, TComparisonAlwaysConstantRule.Outcome('>', -1, 0, 255));
  Assert.AreEqual(0, TComparisonAlwaysConstantRule.Outcome('>', 255, 0, 255));
  Assert.AreEqual(0, TComparisonAlwaysConstantRule.Outcome('=', 256, 0, 255));
  Assert.AreEqual(-1, TComparisonAlwaysConstantRule.Outcome('=', 255, 0, 255));
  Assert.AreEqual(1, TComparisonAlwaysConstantRule.Outcome('<>', -1, 0, 255));
  Assert.AreEqual(-1, TComparisonAlwaysConstantRule.Outcome('<>', 0, 0, 255));
end;

procedure TComparisonAlwaysConstantTests.OffAndExclude;
var
  Source: string;
begin
  Source := Routine('  Rest: Cardinal;'#10, '  if Rest >= 0 then'#10'    Exit;'#10);
  Assert.AreEqual(1, Integer(Length(ComparisonFindings(Source, '', 'Source/Zaehler.pas'))));
  Assert.AreEqual(0, Integer(Length(ComparisonFindings(Source, '{"rules": {"comparison-always-constant": "off"}}',
    'Source/Zaehler.pas'))));
  Assert.AreEqual(0, Integer(Length(ComparisonFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Zaehler.pas'))));
  Assert.AreEqual(0, Integer(Length(ComparisonFindings(Source,
    '{"rules": {"comparison-always-constant": {"exclude": ["Source/*.pas"]}}}', 'Source/Zaehler.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TComparisonAlwaysConstantTests);

end.
