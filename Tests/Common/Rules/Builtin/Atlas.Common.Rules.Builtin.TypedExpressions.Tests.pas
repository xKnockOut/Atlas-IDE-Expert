unit Atlas.Common.Rules.Builtin.TypedExpressions.Tests;

// Tests der Regeln mit Ausdruckstypen (Gruppe „Compiler vorab“):
// comparison-always-constant (#1011): Beispiel aus dem Issue, immer falsche
// und gespiegelte Vergleiche, benannte Konstanten, Felder aus dem Index,
// case-Marken außerhalb des Bereichs, bedingte Deklarationen, stille Fälle,
// Abschalten; Konstanten mit Typumwandlung und UInt64 (#1324).
// constant-initializer-mismatch (#1015): Beispiel mit Korrektur, zu viele
// Einträge, Teilbereiche, Boolean, mehrere Dimensionen, benannte Array-Typen,
// Aufzählungen aus dem Index, Record-Felder in falscher Reihenfolge, bedingte
// Einträge, stille Fälle, Abschalten.
// case-selector-not-ordinal (#1067): Beispiel mit IndexStr-Korrektur samt
// uses, Gleitkomma und Klassen, for mit Double, case-Marken und Arraygrenzen
// aus Variablen, stille Fälle, Abschalten.
// suspicious-string-pointer-cast (#1080): Beispiel mit drei Korrekturen,
// PAnsiChar auf Unicode-Strings, RawByteString und UTF8String aus System,
// Deklarationskorrektur nur für eigene Einzelvariablen, stille Fälle,
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
    procedure LengthIsNeverNegative;
    [Test]
    procedure CaseLabelsOutsideRange;
    [Test]
    procedure ConditionalDeclarationIsSilent;
    [Test]
    procedure PossibleComparisonsAreSilent;
    [Test]
    procedure CastConstantsAndUInt64;
    [Test]
    procedure OutcomeTable;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TConstantInitializerMismatchTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure TooManyAndSubranges;
    [Test]
    procedure DimensionsAndNamedTypes;
    [Test]
    procedure EnumFromIndex;
    [Test]
    procedure RecordFieldOrder;
    [Test]
    procedure MatchingAndUnsureAreSilent;
    [Test]
    procedure Placeholders;
    [Test]
    procedure OffAndExclude;
    /// <summary>#1138: () setzt alle Felder bzw. Elemente auf null und ist kein Befund.</summary>
    [Test]
    procedure EmptyInitializerIsSilent;
    /// <summary>#1323: Zwei Konstanten mit je 20.000 Elementen. Jedes Element fragt nach dem Typ, dessen Name
    /// hinter allen Elementen der ersten Konstante steht; die Suche nach dem Token darf nicht linear sein.</summary>
    [Test]
    [Category('Benchmark')]
    procedure LargeConstantArraysStayFast;
  end;

  [TestFixture]
  TCaseSelectorNotOrdinalTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure FloatsAndClasses;
    [Test]
    procedure ForWithFloatCounter;
    [Test]
    procedure VariablesAsConstants;
    [Test]
    procedure OrdinalAndUnknownAreSilent;
    /// <summary>Explizite Typargumente: nur die generische Überladung zählt (TJSONObject.GetValue&lt;Integer&gt;).
    /// </summary>
    [Test]
    procedure GenericMethodWithTypeArguments;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TSuspiciousStringPointerCastTests = class
  public
    [Test]
    procedure IssueExampleWithFixes;
    [Test]
    procedure AnsiPointerOnUnicodeString;
    [Test]
    procedure SystemStringTypes;
    [Test]
    procedure DeclarationFixOnlyForOwnSingleVariable;
    [Test]
    procedure MatchingAndUnknownAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.TypedExpressions,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert,
  System.Diagnostics;

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

procedure TComparisonAlwaysConstantTests.CastConstantsAndUInt64;
var
  mFound: TArray<TRuleFinding>;
begin
  // Minimalfall aus #1324 (PascalScript): InvalidVal = Cardinal(-1) ist 4294967295, der Vergleich also offen.
  mFound := ComparisonFindings('unit Zaehler;'#10'interface'#10'implementation'#10'const'#10 +
    '  InvalidVal = Cardinal(-1);'#10'procedure Pruefen;'#10'var'#10'  P: Cardinal;'#10'  U: UInt64;'#10'begin'#10 +
    '  if P <> InvalidVal then'#10'    Exit;'#10'  if P = Cardinal(-1) then'#10'    Exit;'#10 +
    '  if U > UInt64(High(Int64)) then'#10'    Exit;'#10'  if U <= High(Int64) then'#10'    Exit;'#10 +
    '  if P <> -1 then'#10'    Exit;'#10'end;'#10'end.');
  // Gegentest: -1 ohne Umwandlung liegt weiter außerhalb von Cardinal.
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('P ist Cardinal; P <> -1 ist immer wahr (wie W1022).', mFound[0].Message);
end;

procedure TComparisonAlwaysConstantTests.LengthIsNeverNegative;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ComparisonFindings(Routine('  S: string;'#10'  A: TArray<Integer>;'#10,
    '  if Length(S) < 0 then'#10'    Exit;'#10'  if Length(A) >= 0 then'#10'    Exit;'#10'  if 0 > Length(S) then'#10 +
    '    Exit;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Length(S) ist nie negativ; Length(S) < 0 ist immer falsch (dcc meldet das nicht).',
    Found[0].Message);
  Assert.AreEqual('Length(A) ist nie negativ; Length(A) >= 0 ist immer wahr (dcc meldet das nicht).',
    Found[1].Message);
  Assert.AreEqual('Length(S) ist nie negativ; 0 > Length(S) ist immer falsch (dcc meldet das nicht).',
    Found[2].Message);
  // Eigene Funktion Length: kann negativ sein.
  Assert.AreEqual(0, Integer(Length(ComparisonFindings('unit Zaehler;'#10'interface'#10'implementation'#10 +
    'function Length(const S: string): Integer;'#10'begin'#10'  Result := -1;'#10'end;'#10 +
    'procedure Pruefen(const S: string);'#10'begin'#10'  if Length(S) < 0 then'#10'    Exit;'#10'end;'#10'end.'))));
end;

procedure TComparisonAlwaysConstantTests.CaseLabelsOutsideRange;
var
  Found: TArray<TRuleFinding>;
begin
  // 300 passt auch als Zahl mit Vorzeichen nicht in 8 Bit: Das meldet dcc als Fehler, hier
  // constant-expression-error (wie E1012, #1372); -1 bleibt hier.
  Found := ComparisonFindings(Routine('  B: Byte;'#10,
    '  case B of'#10'    1, 300, -1:'#10'      Exit;'#10'    250..400:'#10'      Exit;'#10'    256..300:'#10 +
    '      Exit;'#10'    -5..-1:'#10'      Exit;'#10'  end;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('-1 liegt außerhalb des Bereichs von Byte; der Zweig wird nie ausgeführt (wie W1018).',
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
    '  if L > 2147483647 then'#10'    Exit;'#10 +
    '  if C - 1 >= 0 then'#10'    Exit;'#10'  if Stufe > 5 then'#10'    Exit;'#10 +
    '  if Unbekannt >= 0 then'#10'    Exit;'#10'  if Length(S) > 0 then'#10'    Exit;'#10'  if D >= 0 then'#10'    Exit;'#10'  if C >= I then'#10'    Exit;'#10 +
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
  // Obergrenze über High(Int64) (UInt64, #1324): Kein Wert liegt auf oder über ihr.
  Assert.AreEqual(-1, TComparisonAlwaysConstantRule.Outcome('>', High(Int64), 0, High(Int64), False));
  Assert.AreEqual(-1, TComparisonAlwaysConstantRule.Outcome('<=', High(Int64), 0, High(Int64), False));
  Assert.AreEqual(0, TComparisonAlwaysConstantRule.Outcome('>', High(Int64), 0, High(Int64), True));
  Assert.AreEqual(1, TComparisonAlwaysConstantRule.Outcome('>=', 0, 0, High(Int64), False));
  Assert.AreEqual(0, TComparisonAlwaysConstantRule.Outcome('<', 0, 0, High(Int64), False));
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

{ TConstantInitializerMismatchTests }

/// <summary>Meldungen der Treffer, durch " | " getrennt (für Fehlermeldungen der Tests).</summary>
function Messages(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
    Result := Result + Finding.Message + ' | ';
end;

function InitFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TConstantInitializerMismatchRule.Create, ASource);
end;

function InitFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TConstantInitializerMismatchRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit Status mit TStatus (vier Werte) und den Deklarationen ADecls im interface.</summary>
function StatusUnit(const ADecls: string): string;
begin
  Result := 'unit Status;'#10'interface'#10'type'#10'  TStatus = (stNeu, stOffen, stGeschlossen, stArchiviert);'#10 +
    ADecls + 'implementation'#10'end.';
end;

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an (Positionen 0-basiert, Zeilen mit #10).
/// </summary>
function Applied(const AText: string; const AFix: TRuleFix): string;
var
  Lines: TArray<string>;
  Index: Integer;
  Edit: TRuleEdit;
  Line: string;
begin
  Lines := AText.Split([#10]);
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Assert.AreEqual(Edit.Range.StartPos.Line, Edit.Range.EndPos.Line, 'nur einzeilige Edits');
    Line := Lines[Edit.Range.StartPos.Line];
    Lines[Edit.Range.StartPos.Line] := Copy(Line, 1, Edit.Range.StartPos.Character) + Edit.NewText +
      Copy(Line, Edit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, Lines);
end;

procedure TConstantInitializerMismatchTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := StatusUnit('const'#10'  StatusText: array[TStatus] of string ='#10 +
    '    (''Neu'', ''Offen'', ''Geschlossen'');'#10);
  Found := InitFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(ConstantInitializerMismatchRuleId, Found[0].RuleId);
  Assert.AreEqual('TStatus hat 4 Werte, die Konstante 3 Einträge; stArchiviert fehlt (wie E2072).',
    Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Assert.AreEqual(6, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  // Über einer Aufzählung an der richtigen Stelle, mit dem Text aus dem Namen (#667).
  Assert.AreEqual('Fehlenden Eintrag ergänzen (stArchiviert)', Found[0].Fixes[0].Title);
  Fixed := Applied(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('    (''Neu'', ''Offen'', ''Geschlossen'', ''Archiviert'');', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(InitFindings(Fixed))), Fixed);
  // Zwei fehlende Werte.
  Found := InitFindings(StatusUnit('const'#10'  Kurz: array[TStatus] of Integer = (1, 2);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TStatus hat 4 Werte, die Konstante 2 Einträge; stGeschlossen, stArchiviert fehlen (wie E2072).',
    Found[0].Message);
  // Ohne Hinweis auf die Elemente: hinten angehängt und als geschätzt markiert.
  Assert.AreEqual('Fehlende Einträge ergänzen (stGeschlossen, stArchiviert), Stelle geschätzt',
    Found[0].Fixes[0].Title);
  Assert.IsTrue(Pos('(1, 2, 0 {TODO stGeschlossen}, 0 {TODO stArchiviert});', Applied(StatusUnit('const'#10 +
    '  Kurz: array[TStatus] of Integer = (1, 2);'#10), Found[0].Fixes[0])) > 0);
  // Mitten im Wert über den Text der Nachbarn.
  Source := StatusUnit('const'#10'  Texte: array[TStatus] of string = (''Neu'', ''Geschlossen'', ''Archiviert'');'#10);
  Found := InitFindings(Source);
  Assert.AreEqual('TStatus hat 4 Werte, die Konstante 3 Einträge; stOffen fehlt (wie E2072).', Found[0].Message);
  Assert.AreEqual('Fehlenden Eintrag ergänzen (stOffen)', Found[0].Fixes[0].Title);
  Assert.IsTrue(Pos('(''Neu'', ''Offen'', ''Geschlossen'', ''Archiviert'');', Applied(Source, Found[0].Fixes[0])) >
    0);
end;

procedure TConstantInitializerMismatchTests.EmptyInitializerIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(InitFindings(StatusUnit('  TRec = record'#10'    A: Integer;'#10'  end;'#10 +
    'const'#10'  Leer: TRec = ();'#10'  Feld: array[TStatus] of Integer = ( );'#10'var'#10'  Start: TRec = ();'#10)))));
end;

procedure TConstantInitializerMismatchTests.TooManyAndSubranges;
var
  Found: TArray<TRuleFinding>;
begin
  Found := InitFindings(StatusUnit('const'#10'  Max = 2;'#10 +
    '  Viele: array[TStatus] of Integer = (1, 2, 3, 4, 5);'#10 +
    '  Zahlen: array[0..Max] of Integer = (1, 2, 3, 4);'#10 +
    '  Eins: array[1..1] of string = (''a'', ''b'');'#10 +
    '  JaNein: array[Boolean] of string = (''Nein'');'#10 +
    '  Bereich: array[stOffen..stArchiviert] of Integer = (1, 2);'#10 +
    'var'#10'  Start: array[0..1] of Integer = (7);'#10));
  Assert.AreEqual(6, Integer(Length(Found)));
  Assert.AreEqual('TStatus hat 4 Werte, die Konstante 5 Einträge (wie E2072).', Found[0].Message);
  Assert.AreEqual('Überzähligen Eintrag entfernen (5), Stelle geschätzt', Found[0].Fixes[0].Title);
  Assert.AreEqual('0..Max hat 3 Werte, die Konstante 4 Einträge (wie E2072).', Found[1].Message);
  Assert.AreEqual('1..1 hat 1 Wert, die Konstante 2 Einträge (wie E2072).', Found[2].Message);
  Assert.AreEqual('Boolean hat 2 Werte, die Konstante 1 Eintrag (wie E2072).', Found[3].Message);
  Assert.AreEqual(1, Integer(Length(Found[3].Fixes)));
  Assert.AreEqual('stOffen..stArchiviert hat 3 Werte, die Konstante 2 Einträge (wie E2072).', Found[4].Message);
  Assert.AreEqual('0..1 hat 2 Werte, die Konstante 1 Eintrag (wie E2072).', Found[5].Message);
end;

procedure TConstantInitializerMismatchTests.DimensionsAndNamedTypes;
var
  Found: TArray<TRuleFinding>;
begin
  Found := InitFindings(StatusUnit('  TNamen = array[TStatus] of string;'#10'  TIndex = 1..3;'#10 +
    '  TFeld = array[TIndex] of Integer;'#10'const'#10 +
    '  Namen: TNamen = (''a'', ''b'', ''c'', ''d'', ''e'');'#10 +
    '  Feld: TFeld = (1, 2);'#10 +
    '  Matrix: array[0..1, 0..2] of Integer = ((1, 2, 3), (4, 5));'#10 +
    '  Tief: array[0..1] of array[0..1] of Integer = ((1, 2), (3, 4, 5));'#10 +
    '  Liste: array of TFeld = ((1, 2, 3), (1));'#10));
  Assert.AreEqual(5, Integer(Length(Found)));
  Assert.AreEqual('TStatus hat 4 Werte, die Konstante 5 Einträge (wie E2072).', Found[0].Message);
  Assert.AreEqual('TIndex hat 3 Werte, die Konstante 2 Einträge (wie E2072).', Found[1].Message);
  Assert.AreEqual('0..2 hat 3 Werte, die Konstante 2 Einträge (wie E2072).', Found[2].Message);
  Assert.AreEqual('0..1 hat 2 Werte, die Konstante 3 Einträge (wie E2072).', Found[3].Message);
  Assert.AreEqual('TIndex hat 3 Werte, die Konstante 1 Eintrag (wie E2072).', Found[4].Message);
end;

procedure TConstantInitializerMismatchTests.EnumFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Farben;'#10'interface'#10'type'#10 +
    '  TFarbe = (fRot, fGruen, fBlau);'#10'  TCode = (cA = 1, cB = 5);'#10'implementation'#10'end.',
    'C:\Projekt\Farben.pas', nil));
  Found := TRuleAssert.IndexFindings(TConstantInitializerMismatchRule.Create, 'unit Probe;'#10'interface'#10'uses'#10 +
    '  Farben;'#10'const'#10'  Namen: array[TFarbe] of string = (''Rot'', ''Gruen'');'#10 +
    '  Codes: array[TCode] of Integer = (1);'#10'implementation'#10'end.', Index, '', 'Probe.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TFarbe hat 3 Werte, die Konstante 2 Einträge; fBlau fehlt (wie E2072).', Found[0].Message);
end;

procedure TConstantInitializerMismatchTests.RecordFieldOrder;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Punkte;'#10'interface'#10'type'#10'  TPunkt = record'#10'    X, Y: Integer;'#10'    Name: string;'#10 +
    '  end;'#10'const'#10'  Ursprung: TPunkt = (Y: 0; X: 0; Name: ''O'');'#10 +
    '  Ecken: array[0..1] of TPunkt = ((X: 1; Y: 1), (Name: ''B''; X: 2));'#10 +
    '  Gut: TPunkt = (X: 1; Name: ''G'');'#10'implementation'#10'end.';
  Found := InitFindings(Source);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('X steht in TPunkt vor Y; die Felder müssen in der Reihenfolge der Deklaration stehen (wie E2083).',
    Found[0].Message);
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Fixed := Applied(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('Ursprung: TPunkt = (X: 0; Y: 0; Name: ''O'');', Fixed) > 0, Fixed);
  Assert.AreEqual('X steht in TPunkt vor Name; die Felder müssen in der Reihenfolge der Deklaration stehen (wie E2083).',
    Found[1].Message);
  Fixed := Applied(Fixed, InitFindings(Fixed)[0].Fixes[0]);
  Assert.IsTrue(Pos('((X: 1; Y: 1), (X: 2; Name: ''B''))', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(InitFindings(Fixed))), Fixed);
end;

procedure TConstantInitializerMismatchTests.MatchingAndUnsureAreSilent;
begin
  Assert.AreEqual('', Messages(InitFindings(StatusUnit(
    '  TVariante = record'#10'    case Integer of'#10'      0: (A: Integer);'#10'      1: (B: Byte);'#10'  end;'#10 +
    'const'#10'  Gut: array[TStatus] of string = (''a'', ''b'', ''c'', ''d'');'#10 +
    '  Dynamisch: array of Integer = (1, 2, 3);'#10'  Text: array[0..2] of Char = ''abc'';'#10 +
    '  Unbekannt: array[TFremd] of Integer = (1, 2);'#10'  Offen: array[0..Fremd] of Integer = (1);'#10 +
    '  Bedingt: array[0..1] of Integer = (1{$IFDEF X}, 2{$ENDIF});'#10 +
    '  Variante: TVariante = (B: 1);'#10'  Zahl = 5;'#10))));
  // Aufzählung mit bedingtem Wert: Anzahl hängt von der Konfiguration ab.
  Assert.AreEqual(0, Integer(Length(InitFindings('unit Status;'#10'interface'#10'type'#10 +
    '  TStatus = (stNeu{$IFDEF X}, stOffen{$ENDIF});'#10'const'#10'  T: array[TStatus] of string = (''a'');'#10 +
    'implementation'#10'end.'))));
end;

procedure TConstantInitializerMismatchTests.Placeholders;
begin
  Assert.AreEqual('''''', TConstantInitializerMismatchRule.Placeholder('string'));
  Assert.AreEqual('0', TConstantInitializerMismatchRule.Placeholder('Double'));
  Assert.AreEqual('False', TConstantInitializerMismatchRule.Placeholder('boolean'));
  Assert.AreEqual('#0', TConstantInitializerMismatchRule.Placeholder('Char'));
  Assert.AreEqual('nil', TConstantInitializerMismatchRule.Placeholder('Pointer'));
  Assert.AreEqual('', TConstantInitializerMismatchRule.Placeholder('TPunkt'));
  Assert.AreEqual(Int64(2), TConstantInitializerMismatchRule.BuiltinIndexCount('Boolean'));
  Assert.AreEqual(Int64(256), TConstantInitializerMismatchRule.BuiltinIndexCount('AnsiChar'));
  Assert.AreEqual(Int64(0), TConstantInitializerMismatchRule.BuiltinIndexCount('Integer'));
end;

procedure TConstantInitializerMismatchTests.OffAndExclude;
var
  Source: string;
begin
  Source := StatusUnit('const'#10'  T: array[TStatus] of string = (''a'');'#10);
  Assert.AreEqual(1, Integer(Length(InitFindings(Source, '', 'Source/Status.pas'))));
  Assert.AreEqual(0, Integer(Length(InitFindings(Source, '{"rules": {"constant-initializer-mismatch": "off"}}',
    'Source/Status.pas'))));
  Assert.AreEqual(0, Integer(Length(InitFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Status.pas'))));
  Assert.AreEqual(0, Integer(Length(InitFindings(Source,
    '{"rules": {"constant-initializer-mismatch": {"exclude": ["Source/*.pas"]}}}', 'Source/Status.pas'))));
end;

/// <summary>Konstante AName: array[0..ACount - 1] of AType mit den Werten 0 … AValues - 1, 20 je Zeile.</summary>
function LargeConstant(const AName, AType: string; ACount, AValues: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('  ').Append(AName).Append(': array[0..').Append(ACount - 1).Append('] of ').Append(AType);
    mBuilder.Append(' = (');
    for mIndex := 0 to AValues - 1 do
    begin
      if mIndex > 0 then
        mBuilder.Append(', ');
      if mIndex mod 20 = 0 then
        mBuilder.Append(#10'    ');
      mBuilder.Append(mIndex);
    end;
    mBuilder.Append(');'#10);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure TConstantInitializerMismatchTests.LargeConstantArraysStayFast;
const
  cCount = 20000;
  cLimitMs = 20000;
var
  mSource: string;
  mWatch: TStopwatch;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit Tabellen;'#10'interface'#10'type'#10'  TZahl = Integer;'#10'const'#10 +
    LargeConstant('cErste', 'Integer', cCount, cCount) +
    LargeConstant('cZweite', 'TZahl', cCount, cCount) + LargeConstant('cDritte', 'TZahl', cCount, cCount - 1) + 'implementation'#10'end.';
  mWatch := TStopwatch.StartNew;
  mFound := InitFindings(mSource);
  mWatch.Stop;
  System.Writeln(Format('constant-initializer-mismatch: 3 x %d Elemente, %d ms', [cCount,
    mWatch.ElapsedMilliseconds]));
  // Nur die dritte Konstante ist um eins zu kurz.
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < cLimitMs, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  mSource := '';
  mFound := nil;
end;

{ TCaseSelectorNotOrdinalTests }

function CaseFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCaseSelectorNotOrdinalRule.Create, ASource);
end;

function CaseFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCaseSelectorNotOrdinalRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit Befehle mit uses AUses ('' = keins) und der Routine Ausfuehren(Befehl: string).</summary>
function Befehle(const AUses, ABody: string): string;
begin
  Result := 'unit Befehle;'#10'interface'#10'implementation'#10;
  if AUses <> '' then
    Result := Result + 'uses'#10'  ' + AUses + ';'#10;
  Result := Result + 'procedure Ausfuehren(const Befehl: string);'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

/// <summary>Wendet alle Edits an (mehrzeilig), von hinten nach vorn nach Position sortiert.</summary>
function AppliedAll(const AText: string; const AFix: TRuleFix): string;
var
  Edits: TArray<TRuleEdit>;
  Index, Inner: Integer;
  Swap: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Offset: Integer;
  begin
    Offset := 1;
    for Line := 1 to APosition.Line do
      Offset := Pos(#10, AText, Offset) + 1;
    Result := Offset + APosition.Character;
  end;

begin
  Edits := Copy(AFix.Edits);
  for Index := 0 to High(Edits) do
    for Inner := Index + 1 to High(Edits) do
      if OffsetOf(Edits[Inner].Range.StartPos) > OffsetOf(Edits[Index].Range.StartPos) then
      begin
        Swap := Edits[Index];
        Edits[Index] := Edits[Inner];
        Edits[Inner] := Swap;
      end;
  Result := AText;
  for Index := 0 to High(Edits) do
    Result := Copy(Result, 1, OffsetOf(Edits[Index].Range.StartPos) - 1) + Edits[Index].NewText +
      Copy(Result, OffsetOf(Edits[Index].Range.EndPos), MaxInt);
end;

procedure TCaseSelectorNotOrdinalTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Befehle('', '  case Befehl of'#10'    ''neu'': Neu;'#10'    ''ende'': Beenden;'#10'  end;'#10);
  Found := CaseFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(CaseSelectorNotOrdinalRuleId, Found[0].RuleId);
  Assert.AreEqual('case braucht einen ordinalen Typ; Befehl ist string (wie E2001).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(7, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In case IndexStr(…) of umwandeln', Found[0].Fixes[0].Title);
  Fixed := AppliedAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  case IndexStr(Befehl, [''neu'', ''ende'']) of'#10'    0: Neu;'#10'    1: Beenden;'#10, Fixed) > 0,
    Fixed);
  Assert.IsTrue(Pos('uses'#10'  System.StrUtils;', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(CaseFindings(Fixed))), Fixed);
  // System.StrUtils schon eingebunden, mehrere Marken je Zweig.
  Source := Befehle('System.SysUtils, System.StrUtils', '  case Befehl of'#10'    ''a'', ''b'': Neu;'#10 +
    '    ''c'': Beenden;'#10'  else'#10'    Exit;'#10'  end;'#10);
  Found := CaseFindings(Source);
  Fixed := AppliedAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('case IndexStr(Befehl, [''a'', ''b'', ''c'']) of'#10'    0, 1: Neu;'#10'    2: Beenden;', Fixed) > 0,
    Fixed);
  Assert.AreEqual(1, Integer(Pos('System.StrUtils', Fixed) > 0) * Integer(Length(Fixed.Split(['StrUtils'])) - 1));
  // Keine String-Literale als Marken: keine Korrektur.
  Found := CaseFindings(Befehle('', '  case Befehl of'#10'    Name: Neu;'#10'  end;'#10));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TCaseSelectorNotOrdinalTests.FloatsAndClasses;
var
  Found: TArray<TRuleFinding>;
begin
  Found := CaseFindings('unit Werte;'#10'interface'#10'type'#10'  TKunde = class'#10'  end;'#10'implementation'#10 +
    'procedure Pruefen(Wert: Double; Kunde: TKunde; Breit: AnsiString);'#10'begin'#10'  case Wert of'#10 +
    '    1: Exit;'#10'  end;'#10'  case Kunde of'#10'    nil: Exit;'#10'  end;'#10'  case Breit of'#10 +
    '    ''x'': Exit;'#10'  end;'#10'end;'#10'end.');
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('case braucht einen ordinalen Typ; Wert ist Double (wie E2001).', Found[0].Message);
  Assert.AreEqual('case braucht einen ordinalen Typ; Kunde ist TKunde (wie E2001).', Found[1].Message);
  Assert.AreEqual('case braucht einen ordinalen Typ; Breit ist AnsiString (wie E2001).', Found[2].Message);
  // IndexStr nur für string.
  Assert.AreEqual(0, Integer(Length(Found[2].Fixes)));
end;

procedure TCaseSelectorNotOrdinalTests.GenericMethodWithTypeArguments;
const
  Source = 'unit Daten;'#10'interface'#10'type'#10'  TBasis = class'#10 +
    '    function Wert<T>(const APfad: string; AVorgabe: T): T;'#10'  end;'#10'  TObjekt = class(TBasis)'#10 +
    '    function Wert(const AName: string): TBasis; overload;'#10'  end;'#10'implementation'#10 +
    'function TBasis.Wert<T>(const APfad: string; AVorgabe: T): T;'#10'begin'#10'  Result := AVorgabe;'#10'end;'#10 +
    'function TObjekt.Wert(const AName: string): TBasis;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'procedure Lesen(Objekt: TObjekt; Basis: TBasis);'#10'begin'#10 +
    '  case Objekt.Wert<Integer>(''severity'', 1) of'#10'    1: Exit;'#10'  end;'#10 +
    '  case Basis.Wert<Integer>(''severity'', 1) of'#10'    1: Exit;'#10'  end;'#10 +
    '  case Basis.Wert<Double>(''faktor'', 1.0) of'#10'    1: Exit;'#10'  end;'#10'end;'#10'end.';
var
  Found: TArray<TRuleFinding>;
begin
  // Die gleichnamige Überladung ohne Typparameter (wie TJSONObject.GetValue(Name): TJSONValue) gilt nicht.
  Found := CaseFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)), 'nur Double');
  Assert.Contains(Found[0].Message, 'Double');
end;

procedure TCaseSelectorNotOrdinalTests.ForWithFloatCounter;
var
  Found: TArray<TRuleFinding>;
begin
  Found := CaseFindings('unit Schleifen;'#10'interface'#10'implementation'#10'procedure Laufen;'#10'var'#10 +
    '  X: Double;'#10'  I: Integer;'#10'begin'#10'  for X := 1 to 10 do'#10'    Exit;'#10 +
    '  for var Y: Single := 1 to 3 do'#10'    Exit;'#10'  for I := 1 to 10 do'#10'    Exit;'#10 +
    '  for var J := 1 to 3 do'#10'    Exit;'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('for braucht eine ordinale Zählvariable; X ist Double (wie E2032).', Found[0].Message);
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(6, Found[0].Range.StartPos.Character);
  Assert.AreEqual('for braucht eine ordinale Zählvariable; Y ist Single (wie E2032).', Found[1].Message);
end;

procedure TCaseSelectorNotOrdinalTests.VariablesAsConstants;
var
  Found: TArray<TRuleFinding>;
begin
  Found := CaseFindings('unit Marken;'#10'interface'#10'type'#10'  TBox = class'#10'    FMax: Integer;'#10 +
    '    procedure Pruefen(Wert, Grenze: Integer);'#10'  end;'#10'const'#10'  Fest = 3;'#10 +
    '  Getippt: Integer = 4;'#10'var'#10'  Global: Integer;'#10'  Puffer: array[0..Global] of Byte;'#10 +
    'implementation'#10'procedure TBox.Pruefen(Wert, Grenze: Integer);'#10'begin'#10'  case Wert of'#10 +
    '    Fest: Exit;'#10'    Getippt: Exit;'#10'    Grenze: Exit;'#10'    FMax: Exit;'#10'    1..Global: Exit;'#10 +
    '  end;'#10'end;'#10'end.');
  Assert.AreEqual(5, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('Die Arraygrenze Global ist eine Variable, keine Konstante (wie E2026).', Found[0].Message);
  Assert.AreEqual('Die case-Marke Getippt ist eine typisierte Konstante, keine Konstante (wie E2026).',
    Found[1].Message);
  Assert.AreEqual('Die case-Marke Grenze ist ein Parameter, keine Konstante (wie E2026).', Found[2].Message);
  Assert.AreEqual('Die case-Marke FMax ist ein Feld, keine Konstante (wie E2026).', Found[3].Message);
  Assert.AreEqual('Die case-Marke Global ist eine Variable, keine Konstante (wie E2026).', Found[4].Message);
end;

procedure TCaseSelectorNotOrdinalTests.OrdinalAndUnknownAreSilent;
begin
  Assert.AreEqual('', Messages(CaseFindings('unit Ruhig;'#10'interface'#10'type'#10 +
    '  TFarbe = (fRot, fBlau);'#10'const'#10'  Max = 5;'#10'type'#10'  TFeld = array[0..Max] of Integer;'#10 +
    'implementation'#10'procedure Pruefen(I: Integer; C: Char; F: TFarbe; U: TUnbekannt; B: Boolean);'#10 +
    'begin'#10'  case I of'#10'    1, Max: Exit;'#10'    Ord(''a'')..Ord(''z''): Exit;'#10'  end;'#10 +
    '  case C of'#10'    ''a''..''z'': Exit;'#10'  end;'#10'  case F of'#10'    fRot: Exit;'#10'  end;'#10 +
    '  case U of'#10'    1: Exit;'#10'  end;'#10'  case B of'#10'    True: Exit;'#10'  end;'#10 +
    '  for var K := Low(TFeld) to High(TFeld) do'#10'    Exit;'#10'end;'#10'end.')));
end;

procedure TCaseSelectorNotOrdinalTests.OffAndExclude;
var
  Source: string;
begin
  Source := Befehle('', '  case Befehl of'#10'    ''neu'': Exit;'#10'  end;'#10);
  Assert.AreEqual(1, Integer(Length(CaseFindings(Source, '', 'Source/Befehle.pas'))));
  Assert.AreEqual(0, Integer(Length(CaseFindings(Source, '{"rules": {"case-selector-not-ordinal": "off"}}',
    'Source/Befehle.pas'))));
  Assert.AreEqual(0, Integer(Length(CaseFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Befehle.pas'))));
  Assert.AreEqual(0, Integer(Length(CaseFindings(Source,
    '{"rules": {"case-selector-not-ordinal": {"exclude": ["Source/*.pas"]}}}', 'Source/Befehle.pas'))));
end;

{ TSuspiciousStringPointerCastTests }

function CastFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TSuspiciousStringPointerCastRule.Create, ASource);
end;

function CastFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TSuspiciousStringPointerCastRule.Create, ASource, AConfig, APath);
end;

function StringIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10 +
    '  RawByteString = type AnsiString($FFFF);'#10'  UTF8String = type AnsiString(65001);'#10 +
    'function UTF8Encode(const S: string): RawByteString;'#10'implementation'#10 +
    'function UTF8Encode(const S: string): RawByteString;'#10'begin'#10'end;'#10'end.',
    'C:\BDS\source\System.pas', nil));
end;

procedure TSuspiciousStringPointerCastTests.IssueExampleWithFixes;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Routine('  Pfad: AnsiString;'#10, '  DeleteFile(PChar(Pfad));'#10);
  Found := CastFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(SuspiciousStringPointerCastRuleId, Found[0].RuleId);
  Assert.AreEqual('PChar zeigt auf WideChar, Pfad ist AnsiString; die API liest Datenmüll (wie W1044).',
    Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(13, Found[0].Range.StartPos.Character);
  Assert.AreEqual(24, Found[0].Range.EndPos.Character);
  Assert.AreEqual(3, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Pfad als string deklarieren', Found[0].Fixes[0].Title);
  Assert.IsFalse(Found[0].Fixes[0].Alternative);
  Fixed := AppliedAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  Pfad: string;'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(CastFindings(Fixed))), Fixed);
  Assert.AreEqual('In string umwandeln: PChar(string(…))', Found[0].Fixes[1].Title);
  Assert.IsTrue(Found[0].Fixes[1].Alternative);
  Fixed := AppliedAll(Source, Found[0].Fixes[1]);
  Assert.IsTrue(Pos('  DeleteFile(PChar(string(Pfad)));'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(CastFindings(Fixed))), Fixed);
  Assert.AreEqual('Passenden Zeigertyp verwenden: PAnsiChar', Found[0].Fixes[2].Title);
  Fixed := AppliedAll(Source, Found[0].Fixes[2]);
  Assert.IsTrue(Pos('  DeleteFile(PAnsiChar(Pfad));'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(CastFindings(Fixed))), Fixed);
end;

procedure TSuspiciousStringPointerCastTests.AnsiPointerOnUnicodeString;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Routine('  S: string;'#10'  W: WideString;'#10'  U: UnicodeString;'#10'  A: AnsiString;'#10,
    '  Ausgeben(PAnsiChar(S));'#10'  Ausgeben(PAnsiChar(W));'#10'  Ausgeben(PAnsiChar((U)));'#10 +
    '  Ausgeben(PWideChar(A));'#10);
  Found := CastFindings(Source);
  Assert.AreEqual(4, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('PAnsiChar zeigt auf AnsiChar, S ist string; die API liest nur das erste Zeichen (wie W1044).',
    Found[0].Message);
  Assert.AreEqual('PAnsiChar zeigt auf AnsiChar, W ist WideString; die API liest nur das erste Zeichen (wie W1044).',
    Found[1].Message);
  Assert.AreEqual('PAnsiChar zeigt auf AnsiChar, U ist UnicodeString; die API liest nur das erste Zeichen ' +
    '(wie W1044).', Found[2].Message);
  Assert.AreEqual('PWideChar zeigt auf WideChar, A ist AnsiString; die API liest Datenmüll (wie W1044).',
    Found[3].Message);
  // PAnsiChar: keine Deklarationskorrektur.
  Assert.AreEqual(2, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In AnsiString umwandeln: PAnsiChar(AnsiString(…))', Found[0].Fixes[0].Title);
  Assert.IsFalse(Found[0].Fixes[0].Alternative);
  Fixed := AppliedAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  Ausgeben(PAnsiChar(AnsiString(S)));'#10, Fixed) > 0, Fixed);
  Assert.AreEqual('Passenden Zeigertyp verwenden: PChar', Found[0].Fixes[1].Title);
  Fixed := AppliedAll(Source, Found[0].Fixes[1]);
  Assert.IsTrue(Pos('  Ausgeben(PChar(S));'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(3, Integer(Length(CastFindings(Fixed))), Fixed);
  // Klammern bleiben in der Umwandlung erhalten.
  Fixed := AppliedAll(Source, Found[2].Fixes[0]);
  Assert.IsTrue(Pos('  Ausgeben(PAnsiChar(AnsiString((U))));'#10, Fixed) > 0, Fixed);
end;

procedure TSuspiciousStringPointerCastTests.SystemStringTypes;
var
  Found: TArray<TRuleFinding>;
begin
  Found := TRuleAssert.IndexFindings(TSuspiciousStringPointerCastRule.Create, Routine(
    '  R: RawByteString;'#10'  U8: UTF8String;'#10'  S: string;'#10,
    '  Ausgeben(PChar(R));'#10'  Ausgeben(PWideChar(U8));'#10'  Ausgeben(PChar(UTF8Encode(S)));'#10 +
    '  Ausgeben(PAnsiChar(U8));'#10'  Ausgeben(PAnsiChar(UTF8Encode(S)));'#10), StringIndex, '', 'Zaehler.pas');
  Assert.AreEqual(3, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('PChar zeigt auf WideChar, R ist RawByteString; die API liest Datenmüll (wie W1044).',
    Found[0].Message);
  Assert.AreEqual('PWideChar zeigt auf WideChar, U8 ist UTF8String; die API liest Datenmüll (wie W1044).',
    Found[1].Message);
  Assert.AreEqual('PChar zeigt auf WideChar, UTF8Encode(S) ist RawByteString; die API liest Datenmüll ' +
    '(wie W1044).', Found[2].Message);
  // Deklaration R: RawByteString wird string; Funktionsergebnis: nur Umwandlung und Zeigertyp.
  Assert.AreEqual('R als string deklarieren', Found[0].Fixes[0].Title);
  Assert.AreEqual(2, Integer(Length(Found[2].Fixes)));
end;

procedure TSuspiciousStringPointerCastTests.DeclarationFixOnlyForOwnSingleVariable;
var
  Found: TArray<TRuleFinding>;
begin
  Found := CastFindings('unit Pfade;'#10'interface'#10'type'#10'  TDatei = class'#10'    FName: AnsiString;'#10 +
    '    procedure Loeschen(const Ziel: AnsiString);'#10'  end;'#10'implementation'#10 +
    'procedure TDatei.Loeschen(const Ziel: AnsiString);'#10'var'#10'  A, B: AnsiString;'#10 +
    '  C: AnsiString; // Kommentar'#10'begin'#10'  DeleteFile(PChar(Ziel));'#10'  DeleteFile(PChar(FName));'#10 +
    '  DeleteFile(PChar(B));'#10'  DeleteFile(PChar(A));'#10'  DeleteFile(PChar(C));'#10'end;'#10'end.');
  Assert.AreEqual(5, Integer(Length(Found)), Messages(Found));
  // Parameter, Feld, zwei Namen in einer Deklaration: nur Umwandlung und Zeigertyp.
  Assert.AreEqual(2, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual(2, Integer(Length(Found[1].Fixes)));
  Assert.AreEqual(2, Integer(Length(Found[2].Fixes)));
  Assert.AreEqual(2, Integer(Length(Found[3].Fixes)));
  Assert.AreEqual(3, Integer(Length(Found[4].Fixes)));
  Assert.AreEqual('C als string deklarieren', Found[4].Fixes[0].Title);
end;

procedure TSuspiciousStringPointerCastTests.MatchingAndUnknownAreSilent;
begin
  Assert.AreEqual('', Messages(CastFindings(Routine('  S: string;'#10'  A: AnsiString;'#10'  P: PAnsiChar;'#10 +
    '  Bytes: TBytes;'#10'  C: Char;'#10 +
    '  {$IFDEF ANSI}'#10'  Wechselnd: AnsiString;'#10'  {$ELSE}'#10'  Wechselnd: string;'#10'  {$ENDIF}'#10,
    '  Ausgeben(PChar(S));'#10'  Ausgeben(PWideChar(S));'#10'  Ausgeben(PAnsiChar(A));'#10 +
    '  Ausgeben(PChar(''abc''));'#10'  Ausgeben(PAnsiChar(''abc''));'#10'  S := string(P);'#10 +
    '  Ausgeben(PWideChar(Bytes));'#10'  Ausgeben(PChar(Unbekannt));'#10'  Ausgeben(PChar(S + A));'#10 +
    '  Ausgeben(PChar(Wechselnd));'#10'  Ausgeben(PChar(string(A)));'#10'  Ausgeben(PAnsiChar(AnsiString(S)));'#10))));
end;

procedure TSuspiciousStringPointerCastTests.OffAndExclude;
var
  Source: string;
begin
  Source := Routine('  Pfad: AnsiString;'#10, '  DeleteFile(PChar(Pfad));'#10);
  Assert.AreEqual(1, Integer(Length(CastFindings(Source, '', 'Source/Zaehler.pas'))));
  Assert.AreEqual(0, Integer(Length(CastFindings(Source, '{"rules": {"suspicious-string-pointer-cast": "off"}}',
    'Source/Zaehler.pas'))));
  Assert.AreEqual(0, Integer(Length(CastFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Zaehler.pas'))));
  Assert.AreEqual(0, Integer(Length(CastFindings(Source,
    '{"rules": {"suspicious-string-pointer-cast": {"exclude": ["Source/*.pas"]}}}', 'Source/Zaehler.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TComparisonAlwaysConstantTests);
  TDUnitX.RegisterTestFixture(TConstantInitializerMismatchTests);
  TDUnitX.RegisterTestFixture(TCaseSelectorNotOrdinalTests);
  TDUnitX.RegisterTestFixture(TSuspiciousStringPointerCastTests);

end.
