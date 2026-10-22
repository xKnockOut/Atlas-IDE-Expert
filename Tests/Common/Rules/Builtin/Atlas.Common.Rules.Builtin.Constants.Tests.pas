unit Atlas.Common.Rules.Builtin.Constants.Tests;

// Tests der Regeln für Konstanten und Zahlen.
// constant-expression-error (#992): Beispiel aus dem Issue, korrigierte Form,
// Überlauf, Bereich mit Untergrenze über der Obergrenze, Wert außerhalb des
// Typs (W1012 als Warnung), zu große Hex-Literale, Konstanten aus anderen
// Units und aus {$IF}-Zweigen, stille Fälle, Abschalten.
// default-parameter-invalid (#993): Beispiel mit Korrektur samt Implementierung,
// mehrere Namen mit einem Standardwert, var/out, Record, statisches Array und
// Mengen über 4 Byte,
// Prozedurtypen, stille Fälle, Abschalten.
// signed-unsigned-mix (#1012): Beispiel mit UInt64 (W1073), Vergleich und
// Rechnung mit Cardinal (W1023/W1024), Korrektur, Felder und Funktionen aus dem
// Index, stille Fälle (Byte/Word, Cardinal mit Int64, Literale, Konstanten),
// Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConstantExpressionErrorTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure CorrectedAndUnknownAreSilent;
    [Test]
    procedure OverflowBeyondUInt64;
    [Test]
    procedure LowBoundAboveHighBound;
    [Test]
    procedure ValueOutsideTypeIsWarning;
    [Test]
    procedure TooLargeHexLiteral;
    [Test]
    procedure ConstantFromOtherUnit;
    [Test]
    procedure ConditionalConstantsStaySilent;
    [Test]
    procedure OffGroupAndExclude;
    [Test]
    procedure RuleIsRegistered;
  end;

  [TestFixture]
  TDefaultParameterInvalidTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure GroupedNamesAreSplit;
    [Test]
    procedure VarOutAndTypesWithoutDefaults;
    [Test]
    procedure ValidDefaultsAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TSignedUnsignedMixTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure CardinalWithInteger;
    [Test]
    procedure FixWrapsUnsignedOperand;
    [Test]
    procedure MembersFromIndex;
    [Test]
    procedure SafeCombinationsAreSilent;
    [Test]
    procedure OffGroupAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Constants,
  Atlas.Tests.RuleAssert;

function ConstantFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TConstantExpressionErrorRule.Create, ASource);
end;

function ConstantFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TConstantExpressionErrorRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit mit ADeclarations im interface-Teil und AStatements in einer Prozedur.</summary>
function Werte(const ADeclarations, AStatements: string): string;
begin
  Result := 'unit Werte;'#10'interface'#10 + ADeclarations + 'implementation'#10'procedure Rechnen;'#10 +
    'var'#10'  B: Byte;'#10'  C: Cardinal;'#10'  I: Integer;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ConstantFindings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

procedure Silent(const ASource: string);
begin
  Assert.AreEqual(0, Integer(Length(ConstantFindings(ASource))), ASource);
end;

{ TConstantExpressionErrorTests }

procedure TConstantExpressionErrorTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ConstantFindings(Werte('const'#10'  MaxEintraege = 100;'#10'  Seiten = 0;'#10 +
    '  ProSeite = MaxEintraege div Seiten;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Division durch null in einem konstanten Ausdruck (Seiten = 0, wie E2098).', Found[0].Message);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(13, Found[0].Range.StartPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  // Teiler als Ausdruck und mod, auch in Anweisungen.
  Assert.AreEqual('Division durch null in einem konstanten Ausdruck (wie E2098).',
    OnlyMessage(Werte('', '  I := 10 mod (2 - 2);'#10)));
end;

procedure TConstantExpressionErrorTests.CorrectedAndUnknownAreSilent;
begin
  Silent(Werte('const'#10'  MaxEintraege = 100;'#10'  Seiten = 5;'#10'  ProSeite = MaxEintraege div Seiten;'#10,
    ''));
  // Linke Seite unbekannt, Teiler unbekannt, Gleitkomma.
  Silent(Werte('', '  I := I div 1;'#10'  I := I div C;'#10'  I := Round(1 / 2);'#10));
  Silent(Werte('const'#10'  Gross = High(Int64) + 1;'#10'  Klein = Low(Int64);'#10'  Mitte = 1000 * 1000;'#10,
    ''));
end;

procedure TConstantExpressionErrorTests.OverflowBeyondUInt64;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ConstantFindings(Werte('const'#10'  Riesig = 1000000 * 1000000 * 1000000 * 1000;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Überlauf in einem konstanten Ausdruck: Das Ergebnis passt in keinen Ganzzahltyp (wie E2099).',
    Found[0].Message);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(11, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(ConstantFindings(Werte('const'#10'  Tief = Low(Int64) - SizeOf(Int64);'#10,
    '')))));
end;

procedure TConstantExpressionErrorTests.LowBoundAboveHighBound;
begin
  Assert.AreEqual('Die Untergrenze 5 liegt über der Obergrenze 1 (wie E2011).',
    OnlyMessage(Werte('type'#10'  TFeld = array[5..1] of Integer;'#10, '')));
  Assert.AreEqual('Die Untergrenze 3 liegt über der Obergrenze 2 (wie E2011).',
    OnlyMessage(Werte('type'#10'  TFarbe = (Rot, Gruen, Blau, Gelb);'#10'  TTeil = Gelb..Blau;'#10, '')));
  Silent(Werte('type'#10'  TFeld = array[1..5] of Integer;'#10'  TZeichen = ''a''..''z'';'#10 +
    '  TFarbe = (Rot, Gruen);'#10'  TTeil = Rot..Gruen;'#10, ''));
end;

procedure TConstantExpressionErrorTests.ValueOutsideTypeIsWarning;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ConstantFindings(Werte('const'#10'  Grenze: Byte = 300;'#10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('300 liegt außerhalb des Bereichs von Byte (0..255, wie W1012).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual('300 liegt außerhalb des Bereichs von Byte (0..255, wie W1012).',
    OnlyMessage(Werte('', '  B := 300;'#10)));
  Assert.AreEqual('-1 liegt außerhalb des Bereichs von Cardinal (0..4294967295, wie W1012).',
    OnlyMessage(Werte('', '  C := -1;'#10)));
  Assert.AreEqual('150 liegt außerhalb des Bereichs von TProzent (0..100, wie W1012).',
    OnlyMessage(Werte('type'#10'  TProzent = 0..100;'#10'var'#10'  Anteil: TProzent;'#10, '  Anteil := 150;'#10)));
  Assert.AreEqual('256 liegt außerhalb des Bereichs von Byte (0..255, wie W1012).',
    OnlyMessage(Werte('const'#10'  Basis = 255;'#10'var'#10'  Zaehler: Byte = Basis + 1;'#10, '')));
  Silent(Werte('const'#10'  Grenze: Byte = 255;'#10'  Wort: Word = 300;'#10, '  B := 200;'#10'  I := -1;'#10 +
    '  C := 4000000000;'#10));
end;

procedure TConstantExpressionErrorTests.TooLargeHexLiteral;
begin
  Assert.AreEqual('Ganzzahlkonstante zu groß: $1FFFFFFFFFFFFFFFF passt nicht in 64 Bit (wie E2102).',
    OnlyMessage(Werte('const'#10'  Maske = $1FFFFFFFFFFFFFFFF;'#10, '')));
  Assert.IsTrue(TConstantExpressionErrorRule.TooLargeLiteral('%1' + StringOfChar('0', 64)));
  Assert.IsFalse(TConstantExpressionErrorRule.TooLargeLiteral('$FFFFFFFFFFFFFFFF'));
  Assert.IsFalse(TConstantExpressionErrorRule.TooLargeLiteral('$0000FFFFFFFFFFFFFFFF'));
  Assert.IsFalse(TConstantExpressionErrorRule.TooLargeLiteral('99999999999999999999'));
  Assert.IsFalse(TConstantExpressionErrorRule.TooLargeLiteral('1.5e300'));
  Silent(Werte('const'#10'  Maske = $FFFFFFFFFFFFFFFF;'#10, ''));
end;

procedure TConstantExpressionErrorTests.ConstantFromOtherUnit;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Grenzen;'#10'interface'#10'const'#10'  Keine = 0;'#10 +
    '  Viele = 50;'#10'implementation'#10'end.', 'C:\Projekt\Grenzen.pas', nil));
  Found := TRuleAssert.IndexFindings(TConstantExpressionErrorRule.Create, 'unit Werte;'#10'interface'#10 +
    'uses'#10'  Grenzen;'#10'const'#10'  A = Viele div Keine;'#10'  B = Viele div 5;'#10'implementation'#10'end.',
    Index, '', 'Werte.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Division durch null in einem konstanten Ausdruck (Keine = 0, wie E2098).', Found[0].Message);
end;

procedure TConstantExpressionErrorTests.ConditionalConstantsStaySilent;
begin
  // Seiten ist je nach Konfiguration 0 oder 5: ohne sichere Aussage keine Meldung.
  Silent(Werte('const'#10'{$IFDEF KLEIN}'#10'  Seiten = 0;'#10'{$ELSE}'#10'  Seiten = 5;'#10'{$ENDIF}'#10 +
    '  ProSeite = 100 div Seiten;'#10, ''));
  // Im selben Zweig gilt der Wert.
  Assert.AreEqual(1, Integer(Length(ConstantFindings(Werte('const'#10'{$IFDEF KLEIN}'#10'  Seiten = 0;'#10 +
    '  ProSeite = 100 div Seiten;'#10'{$ENDIF}'#10, '')))));
end;

procedure TConstantExpressionErrorTests.OffGroupAndExclude;
var
  Source: string;
begin
  Source := Werte('const'#10'  Seiten = 0;'#10'  ProSeite = 100 div Seiten;'#10, '');
  Assert.AreEqual(1, Integer(Length(ConstantFindings(Source, '', 'Source/Werte.pas'))));
  Assert.AreEqual(0, Integer(Length(ConstantFindings(Source, '{"rules": {"constant-expression-error": "off"}}',
    'Source/Werte.pas'))));
  Assert.AreEqual(0, Integer(Length(ConstantFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Werte.pas'))));
  Assert.AreEqual(0, Integer(Length(ConstantFindings(Source,
    '{"rules": {"constant-expression-error": {"exclude": ["Source/*.pas"]}}}', 'Source/Werte.pas'))));
end;

procedure TConstantExpressionErrorTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = ConstantExpressionErrorRuleId then
      Found := True;
  Assert.IsTrue(Found, ConstantExpressionErrorRuleId);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = DefaultParameterInvalidRuleId then
      Found := True;
  Assert.IsTrue(Found, DefaultParameterInvalidRuleId);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = SignedUnsignedMixRuleId then
      Found := True;
  Assert.IsTrue(Found, SignedUnsignedMixRuleId);
end;

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetIn(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index + APosition.Character;
end;

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an (nach Position sortiert).</summary>
function ApplyAll(const AText: string; const AFix: TRuleFix): string;
var
  Edits: TArray<TRuleEdit>;
  Index, Inner, Start, Stop: Integer;
  Swap: TRuleEdit;
begin
  Edits := Copy(AFix.Edits);
  for Index := 0 to High(Edits) do
    for Inner := Index + 1 to High(Edits) do
      if OffsetIn(AText, Edits[Inner].Range.StartPos) > OffsetIn(AText, Edits[Index].Range.StartPos) then
      begin
        Swap := Edits[Index];
        Edits[Index] := Edits[Inner];
        Edits[Inner] := Swap;
      end;
  Result := AText;
  for Index := 0 to High(Edits) do
  begin
    Start := OffsetIn(Result, Edits[Index].Range.StartPos);
    Stop := OffsetIn(Result, Edits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start - 1) + Edits[Index].NewText + Copy(Result, Stop, MaxInt);
  end;
end;

{ TDefaultParameterInvalidTests }

function DefaultFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDefaultParameterInvalidRule.Create, ASource);
end;

function DefaultFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDefaultParameterInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit mit der Klasse TPost: AMember im interface, AImplementation danach.</summary>
function Post(const AMember, AImplementation: string): string;
begin
  Result := 'unit Post;'#10'interface'#10'type'#10'  TZiel = class'#10'  end;'#10'  TPunkt = record'#10 +
    '    X: Integer;'#10'  end;'#10'  TPaar = array[0..1] of Integer;'#10'  TPost = class'#10 + AMember +
    '  end;'#10'implementation'#10 + AImplementation + 'end.';
end;

function OnlyDefaultMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := DefaultFindings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

procedure TDefaultParameterInvalidTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Post('    procedure Senden(const Text: string = ''''; Ziel: TZiel);'#10,
    'procedure TPost.Senden(const Text: string; Ziel: TZiel);'#10'begin'#10'end;'#10);
  Found := DefaultFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ziel braucht einen Standardwert, weil ein vorheriger Parameter einen hat (wie E2238).',
    Found[0].Message);
  Assert.AreEqual(10, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Parameter mit Standardwert ans Ende verschieben', Found[0].Fixes[0].Title);
  Fixed := ApplyAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('procedure Senden(Ziel: TZiel; const Text: string = '''');', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('procedure TPost.Senden(Ziel: TZiel; const Text: string);', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(DefaultFindings(Fixed))), Fixed);
  // Mehrere Parameter danach: jeder wird gemeldet, die Korrektur steht am ersten.
  Found := DefaultFindings(Post('    procedure Senden(Text: string = ''''; A: Integer; B: Integer);'#10, ''));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Found[1].Fixes)));
  Fixed := ApplyAll(Post('    procedure Senden(Text: string = ''''; A: Integer; B: Integer);'#10, ''),
    Found[0].Fixes[0]);
  Assert.IsTrue(Pos('procedure Senden(A: Integer; B: Integer; Text: string = '''');', Fixed) > 0, Fixed);
end;

procedure TDefaultParameterInvalidTests.GroupedNamesAreSplit;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Post('    procedure Rand(const Links, Rechts: Integer = 4);'#10, '');
  Found := DefaultFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Links, Rechts: Standardwerte gibt es nur für einzeln deklarierte Parameter (wie E2237).',
    Found[0].Message);
  Assert.AreEqual('Parameter einzeln deklarieren', Found[0].Fixes[0].Title);
  Fixed := ApplyAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('procedure Rand(const Links: Integer = 4; const Rechts: Integer = 4);', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(DefaultFindings(Fixed))), Fixed);
end;

procedure TDefaultParameterInvalidTests.VarOutAndTypesWithoutDefaults;
begin
  Assert.AreEqual('Anzahl ist ein var-Parameter und kann keinen Standardwert haben (wie E2239).',
    OnlyDefaultMessage(Post('    procedure Zaehlen(var Anzahl: Integer = 0);'#10, '')));
  Assert.AreEqual('Fehler ist ein out-Parameter und kann keinen Standardwert haben (wie E2239).',
    OnlyDefaultMessage(Post('    procedure Lesen(out Fehler: string = '''');'#10, '')));
  Assert.AreEqual('Parameter vom Typ TPunkt können keinen Standardwert haben (wie E2268).',
    OnlyDefaultMessage(Post('    procedure Zeigen(const Ort: TPunkt = nil);'#10, '')));
  Assert.AreEqual('Parameter vom Typ TPaar können keinen Standardwert haben (wie E2268).',
    OnlyDefaultMessage(Post('    procedure Zeigen(const Werte: TPaar = nil);'#10, '')));
  // Mengen über 4 Byte (E2146), kleine Mengen gehen.
  Assert.AreEqual('TZeichen ist eine Menge über 4 Byte; Standardwerte gibt es nur für ordinale, Zeiger- und ' +
    'kleine Mengentypen (wie E2146).', OnlyDefaultMessage(Post('    procedure Trennen(Zeichen: TZeichen = [''a'']);'#10,
    '').Replace('  TPost = class'#10, '  TZeichen = set of AnsiChar;'#10'  TPost = class'#10)));
  Assert.AreEqual(1, Integer(Length(DefaultFindings(Post('    procedure Trennen(Werte: TWerte = []);'#10,
    '').Replace('  TPost = class'#10, '  TWerte = set of 0..40;'#10'  TPost = class'#10)))));
  Assert.AreEqual(0, Integer(Length(DefaultFindings(Post('    procedure Malen(Farben: TFarben = [Rot]; ' +
    'Bits: TBits = [1, 5]);'#10, '').Replace('  TPost = class'#10, '  TFarbe = (Rot, Gruen, Blau);'#10 +
    '  TFarben = set of TFarbe;'#10'  TBits = set of 0..31;'#10'  TPost = class'#10)))));
  // Prozedurtypen gelten genauso.
  Assert.AreEqual('B braucht einen Standardwert, weil ein vorheriger Parameter einen hat (wie E2238).',
    OnlyDefaultMessage(Post('', '').Replace('  TPost = class'#10,
    '  TRechnen = procedure(A: Integer = 1; B: Integer);'#10'  TPost = class'#10)));
end;

procedure TDefaultParameterInvalidTests.ValidDefaultsAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(DefaultFindings(Post('    procedure Senden(Ziel: TZiel; const Text: string = '''';' +
    ' Anzahl: Integer = 1; Faktor: Double = 0.5; Z: TZiel = nil);'#10'    procedure Leer(var A, B: Integer);'#10,
    'procedure TPost.Senden(Ziel: TZiel; const Text: string; Anzahl: Integer; Faktor: Double; Z: TZiel);'#10 +
    'begin'#10'end;'#10'procedure TPost.Leer(var A, B: Integer);'#10'begin'#10'end;'#10)))));
end;

procedure TDefaultParameterInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := Post('    procedure Senden(const Text: string = ''''; Ziel: TZiel);'#10, '');
  Assert.AreEqual(1, Integer(Length(DefaultFindings(Source, '', 'Source/Post.pas'))));
  Assert.AreEqual(0, Integer(Length(DefaultFindings(Source, '{"rules": {"default-parameter-invalid": "off"}}',
    'Source/Post.pas'))));
  Assert.AreEqual(0, Integer(Length(DefaultFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Post.pas'))));
  Assert.AreEqual(0, Integer(Length(DefaultFindings(Source,
    '{"rules": {"default-parameter-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Post.pas'))));
end;

{ TSignedUnsignedMixTests }

function MixFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TSignedUnsignedMixRule.Create, ASource);
end;

function MixFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TSignedUnsignedMixRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit mit lokalen Variablen AVariables und den Anweisungen AStatements.</summary>
function Mix(const AVariables, AStatements: string): string;
begin
  Result := 'unit Mix;'#10'interface'#10'implementation'#10'procedure Rechnen;'#10'var'#10 + AVariables +
    'begin'#10 + AStatements + 'end;'#10'end.';
end;

function OnlyMixMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := MixFindings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

procedure TSignedUnsignedMixTests.IssueExample;
begin
  Assert.AreEqual('Int64 und UInt64 gemischt: ein negativer Wert in Delta wird vorzeichenlos gerechnet ' +
    '(wie W1073).', OnlyMixMessage(Mix('  Groesse: UInt64;'#10'  Delta: Int64;'#10'  Grenze: UInt64;'#10,
    '  if Groesse + Delta < Grenze then'#10'    Exit;'#10)));
  Assert.AreEqual('Int64 und UInt64 verglichen: ein negativer Wert in Delta wird vorzeichenlos verglichen ' +
    '(wie W1023).', OnlyMixMessage(Mix('  Groesse: UInt64;'#10'  Delta: Int64;'#10,
    '  if Delta < Groesse then'#10'    Exit;'#10)));
  // Korrigierte Form: beide Operanden Int64.
  Assert.AreEqual(0, Integer(Length(MixFindings(Mix('  Groesse: UInt64;'#10'  Delta: Int64;'#10'  Grenze: Int64;'#10,
    '  if Int64(Groesse) + Delta < Grenze then'#10'    Exit;'#10)))));
end;

procedure TSignedUnsignedMixTests.CardinalWithInteger;
begin
  Assert.AreEqual('Integer und Cardinal verglichen: beide Operanden werden auf Int64 erweitert (wie W1023).',
    OnlyMixMessage(Mix('  Anzahl: Cardinal;'#10'  Index: Integer;'#10, '  if Index < Anzahl then'#10'    Exit;'#10)));
  Assert.AreEqual('Integer und DWORD gemischt: beide Operanden werden auf Int64 erweitert (wie W1024).',
    OnlyMixMessage(Mix('  Anzahl: DWORD;'#10'  Index: Integer;'#10'  Summe: Int64;'#10,
    '  Summe := Anzahl - Index;'#10)));
  // Eigener Alias auf einen vorzeichenlosen Typ.
  Assert.AreEqual(1, Integer(Length(MixFindings('unit Mix;'#10'interface'#10'type'#10'  TZahl = Cardinal;'#10 +
    'implementation'#10'procedure Rechnen;'#10'var'#10'  Zahl: TZahl;'#10'  Index: Integer;'#10'begin'#10 +
    '  if Zahl > Index then'#10'    Exit;'#10'end;'#10'end.'))));
end;

procedure TSignedUnsignedMixTests.FixWrapsUnsignedOperand;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Mix('  Anzahl: Cardinal;'#10'  Index: Integer;'#10, '  if Index < Anzahl then'#10'    Exit;'#10);
  Found := MixFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Anzahl in Int64 umwandeln', Found[0].Fixes[0].Title);
  Assert.IsTrue(Pos('if Index < Int64(Anzahl) then', ApplyAll(Source, Found[0].Fixes[0])) > 0);
  Assert.AreEqual(0, Integer(Length(MixFindings(ApplyAll(Source, Found[0].Fixes[0])))));
end;

procedure TSignedUnsignedMixTests.MembersFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Puffer;'#10'interface'#10'type'#10'  TPuffer = class'#10 +
    '    Groesse: Cardinal;'#10'    function Frei: UInt64;'#10'  end;'#10'implementation'#10 +
    'function TPuffer.Frei: UInt64;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.', 'C:\Projekt\Puffer.pas', nil));
  Found := TRuleAssert.IndexFindings(TSignedUnsignedMixRule.Create, 'unit Mix;'#10'interface'#10'uses'#10 +
    '  Puffer;'#10'implementation'#10'procedure Rechnen(P: TPuffer; Rest: Integer);'#10'begin'#10 +
    '  if P.Groesse > Rest then'#10'    Exit;'#10'  if P.Frei >= Rest then'#10'    Exit;'#10'end;'#10'end.',
    Index, '', 'Mix.pas');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Integer und Cardinal verglichen: beide Operanden werden auf Int64 erweitert (wie W1023).',
    Found[0].Message);
  Assert.AreEqual('Integer und UInt64 verglichen: ein negativer Wert in Rest wird vorzeichenlos verglichen ' +
    '(wie W1023).', Found[1].Message);
end;

procedure TSignedUnsignedMixTests.SafeCombinationsAreSilent;
begin
  // Byte und Word passen in Integer, Cardinal passt in Int64.
  Assert.AreEqual(0, Integer(Length(MixFindings(Mix('  B: Byte;'#10'  W: Word;'#10'  C: Cardinal;'#10 +
    '  I: Integer;'#10'  L: Int64;'#10, '  if (B < I) or (W > I) or (C < L) then'#10'    I := B + I;'#10)))));
  // Literale, Konstanten, gleiche Vorzeichen und unbekannte Typen.
  Assert.AreEqual(0, Integer(Length(MixFindings(Mix('  C: Cardinal;'#10'  D: Cardinal;'#10'  I: Integer;'#10 +
    '  U: UInt64;'#10'  X: TUnbekannt;'#10, '  if (C > 0) or (U > 10) or (C < D) or (I < 5) or (X < U) then'#10 +
    '    C := C + 1;'#10)))));
  // NativeInt und NativeUInt hängen von der Plattform ab.
  Assert.AreEqual(0, Integer(Length(MixFindings(Mix('  N: NativeUInt;'#10'  I: Integer;'#10,
    '  if N > I then'#10'    Exit;'#10)))));
end;

procedure TSignedUnsignedMixTests.OffGroupAndExclude;
var
  Source: string;
begin
  Source := Mix('  Anzahl: Cardinal;'#10'  Index: Integer;'#10, '  if Index < Anzahl then'#10'    Exit;'#10);
  Assert.AreEqual(1, Integer(Length(MixFindings(Source, '', 'Source/Mix.pas'))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Source, '{"rules": {"signed-unsigned-mix": "off"}}',
    'Source/Mix.pas'))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Mix.pas'))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Source,
    '{"rules": {"signed-unsigned-mix": {"exclude": ["Source/*.pas"]}}}', 'Source/Mix.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TConstantExpressionErrorTests);
  TDUnitX.RegisterTestFixture(TDefaultParameterInvalidTests);
  TDUnitX.RegisterTestFixture(TSignedUnsignedMixTests);

end.
