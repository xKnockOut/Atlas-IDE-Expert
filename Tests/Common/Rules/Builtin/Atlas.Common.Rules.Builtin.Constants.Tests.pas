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
// narrowing-assignment (#1013): Beispiel Strom.Size aus dem Index, beide
// Korrekturen, Inline-Variablen, Rechnungen, Aliase, Option types (Gleitkomma,
// W1072/W1066), stille Fälle, standardmäßig aus, Abschalten.
// typed-constant-modified (#1014): Beispiel mit Korrektur, Zuweisung an
// Konstante, Element und Feld, var-Parameter eigener Routinen, {$J-} und
// {$J+}, Abschnitte aufteilen, Konstanten aus anderen Units, 0 statt nil,
// stille Fälle, Abschalten.

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

  [TestFixture]
  TNarrowingAssignmentTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure BothFixes;
    [Test]
    procedure InlineVariablesAndArithmetic;
    [Test]
    procedure TypesOption;
    [Test]
    procedure SafeAssignmentsAreSilent;
    [Test]
    procedure OffByDefaultGroupAndExclude;
  end;

  [TestFixture]
  TTypedConstantModifiedTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure AssignmentsElementsAndFields;
    [Test]
    procedure VarParametersOfOwnRoutines;
    [Test]
    procedure WriteableConstDirective;
    [Test]
    procedure FixSplitsSection;
    [Test]
    procedure ConstantFromOtherUnit;
    [Test]
    procedure ZeroForPointer;
    [Test]
    procedure ReadingAndShadowingAreSilent;
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
  Atlas.Common.Configuration.Parser,
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
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = NarrowingAssignmentRuleId then
      Found := True;
  Assert.IsTrue(Found, NarrowingAssignmentRuleId);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = TypedConstantModifiedRuleId then
      Found := True;
  Assert.IsTrue(Found, TypedConstantModifiedRuleId);
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

{ TNarrowingAssignmentTests }

const
  NarrowingOn = '{"rules": {"narrowing-assignment": "warning"}}';

/// <summary>Index mit der Unit Stroeme: TStrom.Size ist Int64, TStrom.Teil ein Double.</summary>
function StreamIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Stroeme;'#10'interface'#10'type'#10'  TStrom = class'#10 +
    '  private'#10'    function GetSize: Int64;'#10'  public'#10'    Teil: Double;'#10 +
    '    Genau: Extended;'#10'    property Size: Int64 read GetSize;'#10'  end;'#10'implementation'#10 +
    'function TStrom.GetSize: Int64;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.', 'C:\Projekt\Stroeme.pas',
    nil));
end;

/// <summary>Unit, die Stroeme benutzt, mit den Variablen AVariables und den Anweisungen AStatements.</summary>
function Lesen(const AVariables, AStatements: string): string;
begin
  Result := 'unit Lesen;'#10'interface'#10'uses'#10'  Stroeme;'#10'implementation'#10 +
    'procedure Laden(Strom: TStrom);'#10'var'#10 + AVariables + 'begin'#10 + AStatements + 'end;'#10'end.';
end;

function NarrowingFindings(const ASource, AConfig: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.IndexFindings(TNarrowingAssignmentRule.Create, ASource, StreamIndex, AConfig, 'Lesen.pas');
end;

function OnlyNarrowingMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := NarrowingFindings(ASource, NarrowingOn);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

procedure TNarrowingAssignmentTests.IssueExample;
begin
  Assert.AreEqual('Strom.Size ist Int64; die Zuweisung an Integer kann Daten verlieren (wie W1071).',
    OnlyNarrowingMessage(Lesen('  Anzahl: Integer;'#10, '  Anzahl := Strom.Size;'#10)));
  // Korrigierte Formen: ausdrücklich umgewandelt oder passender Zieltyp.
  Assert.AreEqual(0, Integer(Length(NarrowingFindings(Lesen('  Anzahl: Integer;'#10'  Groesse: Int64;'#10,
    '  Anzahl := Integer(Strom.Size);'#10'  Groesse := Strom.Size;'#10), NarrowingOn))));
end;

procedure TNarrowingAssignmentTests.BothFixes;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Lesen('  Anzahl: Integer;'#10, '  Anzahl := Strom.Size;'#10);
  Found := NarrowingFindings(Source, NarrowingOn);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(2, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Ausdrücklich in Integer umwandeln', Found[0].Fixes[0].Title);
  Assert.IsTrue(Pos('Anzahl := Integer(Strom.Size);', ApplyAll(Source, Found[0].Fixes[0])) > 0);
  Assert.AreEqual('Zieltyp auf Int64 vergrößern', Found[0].Fixes[1].Title);
  Assert.IsTrue(Pos('  Anzahl: Int64;', ApplyAll(Source, Found[0].Fixes[1])) > 0);
  Assert.AreEqual(0, Integer(Length(NarrowingFindings(ApplyAll(Source, Found[0].Fixes[1]), NarrowingOn))));
  // Mehrere Namen in einer Deklaration und Felder: nur die Umwandlung.
  Found := NarrowingFindings(Lesen('  Anzahl, Rest: Integer;'#10, '  Anzahl := Strom.Size;'#10), NarrowingOn);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
end;

procedure TNarrowingAssignmentTests.InlineVariablesAndArithmetic;
begin
  Assert.AreEqual('Strom.Size ist Int64; die Zuweisung an Integer kann Daten verlieren (wie W1071).',
    OnlyNarrowingMessage(Lesen('', '  var Anzahl: Integer := Strom.Size;'#10)));
  Assert.AreEqual('Strom.Size - Rest ist Int64; die Zuweisung an Integer kann Daten verlieren (wie W1071).',
    OnlyNarrowingMessage(Lesen('  Anzahl, Rest: Integer;'#10, '  Anzahl := Strom.Size - Rest;'#10)));
  Assert.AreEqual('(Strom.Size + 1) div 2 ist Int64; die Zuweisung an LongInt kann Daten verlieren (wie W1071).',
    OnlyNarrowingMessage(Lesen('  Anzahl: LongInt;'#10, '  Anzahl := (Strom.Size + 1) div 2;'#10)));
  // Eigener Alias auf Int64 als Quelle und auf Integer als Ziel.
  Assert.AreEqual(1, Integer(Length(NarrowingFindings('unit Lesen;'#10'interface'#10'type'#10 +
    '  TGroesse = Int64;'#10'  TZahl = Integer;'#10'implementation'#10'procedure Laden;'#10'var'#10 +
    '  Groesse: TGroesse;'#10'  Zahl: TZahl;'#10'begin'#10'  Zahl := Groesse;'#10'end;'#10'end.', NarrowingOn))));
end;

procedure TNarrowingAssignmentTests.TypesOption;
var
  Source, Config: string;
  Found: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Lesen('  Anzahl: Integer;'#10'  Wert: Single;'#10'  Mittel: Double;'#10,
    '  Anzahl := Strom.Size;'#10'  Wert := Strom.Teil;'#10'  Mittel := Strom.Genau;'#10);
  Assert.AreEqual(1, Integer(Length(NarrowingFindings(Source, NarrowingOn))));
  Config := '{"rules": {"narrowing-assignment": {"severity": "warning", "types": ["Double>Single", ' +
    '"Extended>Double"]}}}';
  Found := NarrowingFindings(Source, Config);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Strom.Teil ist Double; die Zuweisung an Single kann Daten verlieren (wie W1072).',
    Found[0].Message);
  Assert.AreEqual('Strom.Genau ist Extended; die Zuweisung an Double kann Daten verlieren (wie W1066).',
    Found[1].Message);
  // NativeInt>Integer gehört zur Vorgabe.
  Assert.AreEqual(1, Integer(Length(NarrowingFindings(Lesen('  Zeiger: NativeInt;'#10'  Anzahl: Integer;'#10,
    '  Anzahl := Zeiger;'#10), NarrowingOn))));
  TConfigurationParser.Parse('{"rules": {"narrowing-assignment": {"types": "Int64>Integer"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"types" muss eine Liste von Texten sein', Issues[0].Message);
end;

procedure TNarrowingAssignmentTests.SafeAssignmentsAreSilent;
begin
  // Breiterer Zieltyp, Literale, Integer an Int64, Umwandlungen und unbekannte Typen.
  Assert.AreEqual(0, Integer(Length(NarrowingFindings(Lesen('  Anzahl: Integer;'#10'  Groesse: Int64;'#10 +
    '  Wert: Double;'#10'  Fremd: TUnbekannt;'#10, '  Groesse := Strom.Size;'#10'  Groesse := Anzahl;'#10 +
    '  Anzahl := 5;'#10'  Wert := Strom.Size;'#10'  Anzahl := Integer(Strom.Size) + 1;'#10 +
    '  Anzahl := Fremd;'#10'  Anzahl := Strom.Size div Fremd;'#10'  Wert := Strom.Teil;'#10), NarrowingOn))));
end;

procedure TNarrowingAssignmentTests.OffByDefaultGroupAndExclude;
var
  Source: string;
begin
  Source := Lesen('  Anzahl: Integer;'#10, '  Anzahl := Strom.Size;'#10);
  Assert.AreEqual(0, Integer(Length(NarrowingFindings(Source, ''))));
  Assert.AreEqual(1, Integer(Length(NarrowingFindings(Source, NarrowingOn))));
  Assert.AreEqual(0, Integer(Length(NarrowingFindings(Source,
    '{"rules": {"narrowing-assignment": "warning", "group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(NarrowingFindings(Source,
    '{"rules": {"narrowing-assignment": {"severity": "warning", "exclude": ["Lesen.pas"]}}}'))));
end;

{ TTypedConstantModifiedTests }

function TypedFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TTypedConstantModifiedRule.Create, ASource);
end;

function TypedFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TTypedConstantModifiedRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit Zaehlen mit ADeclarations auf Unit-Ebene und AStatements in der Prozedur Zaehle.</summary>
function Zaehlen(const ADeclarations, AStatements: string): string;
begin
  Result := 'unit Zaehlen;'#10'interface'#10 + ADeclarations + 'implementation'#10 +
    'procedure Tausche(var A, B: Integer);'#10'begin'#10'end;'#10 +
    'procedure Zeige(A: Integer; const B: Integer);'#10'begin'#10'end;'#10 +
    'procedure Zaehle;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFindings do
    Result := Result + Finding.Message + #10;
end;

procedure TTypedConstantModifiedTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Zaehlen('const'#10'  Zaehler: Integer = 0;'#10, '  Inc(Zaehler);'#10);
  Found := TypedFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Zaehler ist eine typisierte Konstante und wird verändert (wie W1016).', Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In var mit Initialwert umwandeln', Found[0].Fixes[0].Title);
  Fixed := ApplyAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('interface'#10'var'#10'  Zaehler: Integer = 0;'#10'implementation', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(TypedFindings(Fixed))));
end;

procedure TTypedConstantModifiedTests.AssignmentsElementsAndFields;
begin
  Assert.AreEqual('Zaehler ist eine typisierte Konstante und wird verändert (wie W1017).'#10 +
    'Feld ist eine typisierte Konstante und wird verändert (wie W1017).'#10 +
    'Ursprung ist eine typisierte Konstante und wird verändert (wie W1017).'#10 +
    'Name ist eine typisierte Konstante und wird verändert (wie W1016).'#10,
    Messages(TypedFindings(Zaehlen('type'#10'  TPunkt = record'#10'    X, Y: Integer;'#10'  end;'#10'const'#10 +
    '  Zaehler: Integer = 0;'#10'  Feld: array[0..1] of Integer = (1, 2);'#10 +
    '  Ursprung: TPunkt = (X: 0; Y: 0);'#10'  Name: string = ''abc'';'#10,
    '  Zaehler := 5;'#10'  Feld[0] := 3;'#10'  Ursprung.X := 1;'#10'  Delete(Name, 1, 1);'#10))));
end;

procedure TTypedConstantModifiedTests.VarParametersOfOwnRoutines;
var
  Found: TArray<TRuleFinding>;
begin
  Found := TypedFindings(Zaehlen('const'#10'  Zaehler: Integer = 0;'#10'  Grenze: Integer = 9;'#10,
    '  Tausche(Zaehler, Grenze);'#10'  Zeige(Zaehler, Grenze);'#10));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Zaehler ist eine typisierte Konstante und wird verändert (wie W1016).', Found[0].Message);
  Assert.AreEqual('Grenze ist eine typisierte Konstante und wird verändert (wie W1016).', Found[1].Message);
  Assert.AreEqual(3, Integer(Length(TTypedConstantModifiedRule.VarParameters(
    'procedure Tausche(var A, B: Integer; C: Integer = 0)'))));
  Assert.IsTrue(TTypedConstantModifiedRule.VarParameters('procedure Lies(out A: string; var B)')[1]);
  Assert.IsFalse(TTypedConstantModifiedRule.VarParameters('procedure Tausche(var A, B: Integer; C: Integer)')[2]);
end;

procedure TTypedConstantModifiedTests.WriteableConstDirective;
var
  Found: TArray<TRuleFinding>;
begin
  Found := TypedFindings(Zaehlen('{$J-}'#10'const'#10'  Zaehler: Integer = 0;'#10,
    '  Zaehler := 1;'#10'  Inc(Zaehler);'#10));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Zaehler ist eine typisierte Konstante und kann ohne {$J+} nicht verändert werden (wie E2064).',
    Found[0].Message);
  Assert.AreEqual('Zaehler ist eine typisierte Konstante und kann ohne {$J+} nicht verändert werden (wie E2197).',
    Found[1].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Found := TypedFindings(Zaehlen('{$WRITEABLECONST OFF}'#10'{$J+,H+}'#10'const'#10'  Zaehler: Integer = 0;'#10,
    '  Zaehler := 1;'#10));
  Assert.AreEqual('Zaehler ist eine typisierte Konstante und wird verändert (wie W1017).'#10, Messages(Found));
end;

procedure TTypedConstantModifiedTests.FixSplitsSection;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Zaehlen('const'#10'  Erste = 1;'#10'  Zaehler: Integer = 0;'#10'  Letzte = 2;'#10,
    '  Zaehler := 1;'#10);
  Found := TypedFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Fixed := ApplyAll(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('const'#10'  Erste = 1;'#10'var'#10'  Zaehler: Integer = 0;'#10'const'#10'  Letzte = 2;'#10,
    Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(TypedFindings(Fixed))));
  // Lokale typisierte Konstanten behalten ihren Wert zwischen Aufrufen: keine Korrektur.
  Found := TypedFindings('unit Zaehlen;'#10'interface'#10'implementation'#10'procedure Zaehle;'#10'const'#10 +
    '  Aufrufe: Integer = 0;'#10'begin'#10'  Inc(Aufrufe);'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TTypedConstantModifiedTests.ConstantFromOtherUnit;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Vorgaben;'#10'interface'#10'const'#10 +
    '  Standard: Integer = 4;'#10'  Fest = 5;'#10'implementation'#10'end.', 'C:\Projekt\Vorgaben.pas', nil));
  Found := TRuleAssert.IndexFindings(TTypedConstantModifiedRule.Create, 'unit Zaehlen;'#10'interface'#10'uses'#10 +
    '  Vorgaben;'#10'implementation'#10'procedure Zaehle;'#10'var'#10'  X: Integer;'#10'begin'#10 +
    '  Standard := 8;'#10'  Vorgaben.Standard := 9;'#10'  X := Standard + Fest;'#10'end;'#10'end.',
    Index, '', 'Zaehlen.pas');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Standard ist eine typisierte Konstante und wird verändert (wie W1017).', Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TTypedConstantModifiedTests.ZeroForPointer;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Zaehlen('type'#10'  PKunde = ^Integer;'#10'const'#10'  Leer: Pointer = 0;'#10 +
    '  Text: PChar = 0;'#10'  Kunde: PKunde = 0;'#10'  Ziel: ^Integer = 0;'#10'  Zahl: Integer = 0;'#10 +
    '  Gut: Pointer = nil;'#10, '');
  Found := TypedFindings(Source);
  Assert.AreEqual('Leer ist ein Zeiger; die 0 wird zu nil umgewandelt (wie W1013).'#10 +
    'Text ist ein Zeiger; die 0 wird zu nil umgewandelt (wie W1013).'#10 +
    'Kunde ist ein Zeiger; die 0 wird zu nil umgewandelt (wie W1013).'#10 +
    'Ziel ist ein Zeiger; die 0 wird zu nil umgewandelt (wie W1013).'#10, Messages(Found));
  Assert.AreEqual('nil schreiben', Found[0].Fixes[0].Title);
  Assert.IsTrue(Pos('Leer: Pointer = nil;', ApplyAll(Source, Found[0].Fixes[0])) > 0);
end;

procedure TTypedConstantModifiedTests.ReadingAndShadowingAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(TypedFindings(Zaehlen('const'#10'  Zaehler: Integer = 0;'#10 +
    '  Fest = 3;'#10'  Ziel: PInteger = nil;'#10'var'#10'  Wert: Integer;'#10,
    '  Wert := Zaehler + Fest;'#10'  Zeige(Zaehler, Zaehler);'#10'  Ziel^ := 1;'#10'  Inc(Wert, Zaehler);'#10)))));
  // Eine lokale Variable gleichen Namens verdeckt die Konstante.
  Assert.AreEqual(0, Integer(Length(TypedFindings('unit Zaehlen;'#10'interface'#10'const'#10 +
    '  Zaehler: Integer = 0;'#10'implementation'#10'procedure Zaehle;'#10'var'#10'  Zaehler: Integer;'#10 +
    'begin'#10'  Zaehler := 1;'#10'  Inc(Zaehler);'#10'end;'#10'end.'))));
end;

procedure TTypedConstantModifiedTests.OffGroupAndExclude;
var
  Source: string;
begin
  Source := Zaehlen('const'#10'  Zaehler: Integer = 0;'#10, '  Inc(Zaehler);'#10);
  Assert.AreEqual(1, Integer(Length(TypedFindings(Source, '', 'Source/Zaehlen.pas'))));
  Assert.AreEqual(0, Integer(Length(TypedFindings(Source, '{"rules": {"typed-constant-modified": "off"}}',
    'Source/Zaehlen.pas'))));
  Assert.AreEqual(0, Integer(Length(TypedFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Zaehlen.pas'))));
  Assert.AreEqual(0, Integer(Length(TypedFindings(Source,
    '{"rules": {"typed-constant-modified": {"exclude": ["Source/*.pas"]}}}', 'Source/Zaehlen.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TConstantExpressionErrorTests);
  TDUnitX.RegisterTestFixture(TDefaultParameterInvalidTests);
  TDUnitX.RegisterTestFixture(TSignedUnsignedMixTests);
  TDUnitX.RegisterTestFixture(TNarrowingAssignmentTests);
  TDUnitX.RegisterTestFixture(TTypedConstantModifiedTests);

end.
