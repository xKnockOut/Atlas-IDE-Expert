unit Atlas.Common.Rules.Builtin.StringConversions.Tests;

// Tests der Regel string-conversion (#1377): die Fälle aus
// Tests/Compilermeldungen (W1050, W1057–W1060, W1062, W1068) samt Korrekturen,
// Argumente, RawByteString, UTF8String und WideString aus System, Schalter
// {$WARN} und {$WARNINGS}, Projektoptionen der .dproj, Codepage, Gegenfälle, die dcc ohne Meldung
// übersetzt, und Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStringConversionTests = class
  public
    [Test]
    procedure ImplicitWithFixes;
    [Test]
    procedure ExplicitOnlyWithWarnSwitch;
    [Test]
    procedure ConstantWithLostCharacters;
    [Test]
    procedure ImmutableStringsOnlyWithWarnSwitch;
    [Test]
    procedure WideCharInSetWithFix;
    [Test]
    procedure ArgumentsAndInlineVariables;
    [Test]
    procedure SystemStringTypes;
    [Test]
    procedure SwitchesTurnOffAndRaise;
    [Test]
    procedure ProjectOptions;
    [Test]
    procedure SilentCases;
    [Test]
    procedure ConversionTable;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.StringConversions,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.TextChanges,
  Atlas.Tests.RuleAssert;

/// <summary>Unit Texte mit den Schaltern AHead vor unit, den Deklarationen ADecls (var-Abschnitt von Pruefen)
/// und den Anweisungen ABody. Pruefen beginnt in Zeile 3 + Zeilen von AHead.</summary>
function Routine(const AHead, ADecls, ABody: string): string;
begin
  Result := AHead + 'unit Texte;'#10'interface'#10'implementation'#10'procedure Pruefen;'#10'var'#10 + ADecls +
    'begin'#10 + ABody + 'end;'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TStringConversionRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TStringConversionRule.Create, ASource, AConfig, APath);
end;

/// <summary>Treffer mit den Projektoptionen AProjectWarnings ("IMPLICIT_STRING_CAST=false").</summary>
function Findings(const ASource: string; const AProjectWarnings: TArray<string>): TArray<TRuleFinding>; overload;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.RelativePath := 'Texte.pas';
  mContext.UnitName := 'Texte';
  mContext.Text := ASource;
  mContext.ProjectWarnings := AProjectWarnings;
  Result := TRuleAssert.ContextFindings(TStringConversionRule.Create, mContext, '');
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
    Result := Result + mFinding.Message + ' | ';
end;

function Applied(const ASource: string; const AFix: TRuleFix): string;
begin
  Result := TTextChanges.Apply(ASource, AFix.Edits);
end;

/// <summary>System mit RawByteString und UTF8String wie in der RTL.</summary>
function StringIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10 +
    '  RawByteString = type AnsiString($FFFF);'#10'  UTF8String = type AnsiString(65001);'#10'implementation'#10 +
    'end.', 'C:\BDS\source\System.pas', nil));
end;

{ TStringConversionTests }

procedure TStringConversionTests.ImplicitWithFixes;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // Cm.W1057
  mSource := 'unit Texte;'#10'interface'#10'implementation'#10'function Breit(const AText: AnsiString): string;'#10 +
    'begin'#10'  Result := AText;'#10'end;'#10'end.';
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(StringConversionRuleId, mFound[0].RuleId);
  Assert.AreEqual('AText ist AnsiString; die Zuweisung an Result wandelt implizit um (wie W1057).',
    mFound[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(17, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('Ausdrücklich in string umwandeln', mFound[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  Result := string(AText);'#10, mFixed) > 0, mFixed);
  // Die ausdrückliche Umwandlung meldet dcc nur mit {$WARN EXPLICIT_STRING_CAST ON}.
  Assert.AreEqual('', Messages(Findings(mFixed)));
  // Cm.W1058
  mSource := 'unit Texte;'#10'interface'#10'implementation'#10'function Schmal(const AText: string): AnsiString;'#10 +
    'begin'#10'  Result := AText;'#10'end;'#10'end.';
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('AText ist string; die Zuweisung an Result kann Zeichen verlieren (wie W1058).',
    mFound[0].Message);
  Assert.AreEqual('Ausdrücklich in AnsiString umwandeln', mFound[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  Result := AnsiString(AText);'#10, mFixed) > 0, mFixed);
  Assert.AreEqual('', Messages(Findings(mFixed)));
end;

procedure TStringConversionTests.ExplicitOnlyWithWarnSwitch;
var
  mFound: TArray<TRuleFinding>;
begin
  Assert.AreEqual('', Messages(Findings(Routine('', '  S: string;'#10'  A: AnsiString;'#10,
    '  S := string(A);'#10'  A := AnsiString(S);'#10))));
  // Cm.W1059 und Cm.W1060
  mFound := Findings(Routine('{$WARN EXPLICIT_STRING_CAST ON}'#10'{$WARN EXPLICIT_STRING_CAST_LOSS ON}'#10,
    '  S: string;'#10'  A: AnsiString;'#10, '  S := string(A);'#10'  A := AnsiString(S);'#10 +
    '  A := System.AnsiString(S);'#10'  S := UnicodeString(A);'#10));
  Assert.AreEqual(4, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('A ist AnsiString; ausdrückliche Umwandlung in string (wie W1059).', mFound[0].Message);
  Assert.AreEqual(10, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(16, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('S ist string; die Umwandlung in AnsiString kann Zeichen verlieren (wie W1060).', mFound[1].Message);
  Assert.AreEqual('S ist string; die Umwandlung in AnsiString kann Zeichen verlieren (wie W1060).', mFound[2].Message);
  Assert.AreEqual('A ist AnsiString; ausdrückliche Umwandlung in UnicodeString (wie W1059).', mFound[3].Message);
  // Nur der eingeschaltete Code.
  mFound := Findings(Routine('{$WARN EXPLICIT_STRING_CAST_LOSS ON}'#10, '  S: string;'#10'  A: AnsiString;'#10,
    '  S := string(A);'#10'  A := AnsiString(S);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(10, mFound[0].Range.StartPos.Line);
end;

procedure TStringConversionTests.ConstantWithLostCharacters;
var
  mFound: TArray<TRuleFinding>;
begin
  // Cm.W1062: dcc meldet W1058 und W1062 an derselben Stelle.
  mFound := Findings(Routine('', '  A: AnsiString;'#10, '  A := ''Preis '' + #$20AC#$2603;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('''Preis '' + #$20AC#$2603 enthält Zeichen, die es in der ANSI-Codepage 1252 nicht gibt; ' +
    'die Zuweisung an AnsiString macht daraus ''?'' (wie W1058 und W1062).', mFound[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFound[0].Confidence));
  Assert.AreEqual(7, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFound[0].Range.StartPos.Character);
  // Emoji, CJK und Hebräisch gehen verloren.
  Assert.AreEqual(3, Integer(Length(Findings(Routine('', '  A: AnsiString;'#10,
    '  A := #$D83D#$DE00;'#10'  A := (''Name: '' + #$540D);'#10'  A := #$05D0;'#10)))));
  // € und Umlaute gibt es in 1252; Windows bildet Ā ersatzweise auf A ab: dcc schweigt.
  Assert.AreEqual('', Messages(Findings(Routine('', '  A: AnsiString;'#10'  S: string;'#10'  U: UTF8String;'#10,
    '  A := ''Preis '' + #$20AC;'#10'  A := ''Größe'';'#10'  A := #$0100;'#10'  S := #$2603;'#10 +
    '  U := #$2603;'#10))));
  // Andere Codepage bzw. 0: keine Aussage.
  Assert.AreEqual('', Messages(Findings(Routine('', '  A: AnsiString;'#10, '  A := #$2603;'#10),
    '{"rules": {"string-conversion": {"ansiCodePage": 932}}}', 'Texte.pas')));
  Assert.AreEqual('', Messages(Findings(Routine('', '  A: AnsiString;'#10, '  A := #$2603;'#10),
    '{"rules": {"string-conversion": {"ansiCodePage": 0}}}', 'Texte.pas')));
  // Ohne W1058 bleibt W1062.
  mFound := Findings(Routine('{$WARN IMPLICIT_STRING_CAST_LOSS OFF}'#10, '  A: AnsiString;'#10,
    '  A := #$2603;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.IsTrue(mFound[0].Message.EndsWith('(wie W1062).'), mFound[0].Message);
end;

procedure TStringConversionTests.ImmutableStringsOnlyWithWarnSwitch;
var
  mFound: TArray<TRuleFinding>;
begin
  Assert.AreEqual('', Messages(Findings(Routine('', '  S: string;'#10, '  S[1] := ''x'';'#10))));
  // Cm.W1068
  mFound := Findings(Routine('{$WARN IMMUTABLE_STRINGS ON}'#10, '  S: string;'#10'  A: AnsiString;'#10,
    '  S[1] := ''x'';'#10'  A[1] := ''x'';'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('Zeichen von S direkt geändert; das wird möglicherweise künftig nicht mehr unterstützt ' +
    '(wie W1068).', mFound[0].Message);
  Assert.AreEqual(9, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
end;

procedure TStringConversionTests.WideCharInSetWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // Cm.W1050
  mSource := 'unit Texte;'#10'interface'#10'implementation'#10'function IstZiffer(AZeichen: Char): Boolean;'#10 +
    'begin'#10'  Result := AZeichen in [''0''..''9''];'#10'end;'#10'end.';
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('AZeichen ist Char; im Mengenausdruck wird das Zeichen auf ein Byte gekürzt (wie W1050).',
    mFound[0].Message);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('CharInSet verwenden', mFound[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  Result := CharInSet(AZeichen, [''0''..''9'']);'#10, mFixed) > 0, mFixed);
  Assert.IsTrue(Pos('System.SysUtils', mFixed) > 0, mFixed);
  Assert.AreEqual('', Messages(Findings(mFixed)));
  // Element eines Strings, WideChar, mehrere Einträge; SysUtils schon da: kein uses-Edit.
  mSource := 'unit Texte;'#10'interface'#10'implementation'#10'uses'#10'  SysUtils;'#10 +
    'procedure Pruefen(const S: string; W: WideChar; I: Integer);'#10'begin'#10 +
    '  if S[I] in [''a''..''z'', ''_''] then Exit;'#10'  if not (W in [#9, '' '']) then Exit;'#10'end;'#10'end.';
  mFound := Findings(mSource);
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('S[I] ist Char; im Mengenausdruck wird das Zeichen auf ein Byte gekürzt (wie W1050).',
    mFound[0].Message);
  Assert.AreEqual('W ist WideChar; im Mengenausdruck wird das Zeichen auf ein Byte gekürzt (wie W1050).',
    mFound[1].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes[0].Edits)));
  mFixed := Applied(mSource, mFound[1].Fixes[0]);
  Assert.IsTrue(Pos('  if not (CharInSet(W, [#9, '' ''])) then Exit;'#10, mFixed) > 0, mFixed);
end;

procedure TStringConversionTests.ArgumentsAndInlineVariables;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings('unit Texte;'#10'interface'#10'implementation'#10 +
    'procedure Ausgeben(const AText: string; ANummer: Integer);'#10'begin'#10'end;'#10 +
    'procedure Ablegen(var AText: AnsiString);'#10'begin'#10'end;'#10 +
    'procedure Pruefen(A: AnsiString; S: string);'#10'begin'#10'  Ausgeben(A, 1);'#10'  Ablegen(A);'#10 +
    '  var V: AnsiString := S;'#10'  var W := S;'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('A ist AnsiString; die Übergabe an Ausgeben (AText) wandelt implizit um (wie W1057).',
    mFound[0].Message);
  Assert.AreEqual(11, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(11, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('S ist string; die Zuweisung an V kann Zeichen verlieren (wie W1058).', mFound[1].Message);
  // Überladungen: dcc wählt die passende, die Regel schweigt.
  Assert.AreEqual('', Messages(Findings('unit Texte;'#10'interface'#10'implementation'#10 +
    'procedure Ausgeben(const AText: string); overload;'#10'begin'#10'end;'#10 +
    'procedure Ausgeben(const AText: AnsiString); overload;'#10'begin'#10'end;'#10 +
    'procedure Pruefen(A: AnsiString);'#10'begin'#10'  Ausgeben(A);'#10'end;'#10'end.')));
end;

procedure TStringConversionTests.SystemStringTypes;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.IndexFindings(TStringConversionRule.Create, Routine('', '  R: RawByteString;'#10 +
    '  U: UTF8String;'#10'  W: WideString;'#10'  S: string;'#10'  A: AnsiString;'#10,
    '  S := R;'#10'  R := S;'#10'  U := S;'#10'  S := U;'#10'  W := A;'#10'  A := W;'#10 +
    '  A := R;'#10'  A := U;'#10'  U := A;'#10'  S := W;'#10'  W := S;'#10), StringIndex, '', 'Texte.pas');
  Assert.AreEqual(6, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('R ist RawByteString; die Zuweisung an S wandelt implizit um (wie W1057).', mFound[0].Message);
  Assert.AreEqual('S ist string; die Zuweisung an R kann Zeichen verlieren (wie W1058).', mFound[1].Message);
  Assert.AreEqual('S ist string; die Zuweisung an U wandelt implizit um (wie W1057).', mFound[2].Message);
  Assert.AreEqual('U ist UTF8String; die Zuweisung an S wandelt implizit um (wie W1057).', mFound[3].Message);
  Assert.AreEqual('A ist AnsiString; die Zuweisung an W wandelt implizit um (wie W1057).', mFound[4].Message);
  Assert.AreEqual('W ist WideString; die Zuweisung an A kann Zeichen verlieren (wie W1058).', mFound[5].Message);
end;

procedure TStringConversionTests.SwitchesTurnOffAndRaise;
var
  mFound: TArray<TRuleFinding>;
begin
  // Ab der Stelle des Schalters, wie beim Compiler.
  mFound := Findings(Routine('', '  S: string;'#10'  A: AnsiString;'#10, '  S := A;'#10 +
    '  {$WARN IMPLICIT_STRING_CAST OFF}'#10'  S := A;'#10'  {$WARN IMPLICIT_STRING_CAST DEFAULT}'#10'  S := A;'#10 +
    '  {$WARNINGS OFF}'#10'  S := A;'#10'  {$WARNINGS ON}'#10'  {$WARN IMPLICIT_STRING_CAST ERROR}'#10'  S := A;'#10));
  Assert.AreEqual(3, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[1].Severity));
  Assert.AreEqual(17, mFound[2].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[2].Severity));
  // Schalter in einem Zweig, der nicht sicher mit übersetzt wird: keine Aussage.
  Assert.AreEqual('', Messages(Findings(Routine('{$IFDEF ALT}'#10'{$WARN IMPLICIT_STRING_CAST OFF}'#10'{$ENDIF}'#10,
    '  S: string;'#10'  A: AnsiString;'#10, '  S := A;'#10))));
  Assert.AreEqual('', Messages(Findings(Routine('{$WARN WIDECHAR_REDUCED OFF}'#10, '  C: Char;'#10'  B: Boolean;'#10,
    '  B := C in [''a''];'#10))));
end;

procedure TStringConversionTests.ProjectOptions;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  // DCC_<Bezeichner> der .dproj wie bei dcc; {$WARN} in der Datei gilt danach.
  mSource := Routine('', '  S: string;'#10'  A: AnsiString;'#10, '  S := A;'#10'  S := string(A);'#10);
  Assert.AreEqual('', Messages(Findings(mSource, TArray<string>.Create('IMPLICIT_STRING_CAST=false'))));
  mFound := Findings(mSource, TArray<string>.Create('EXPLICIT_STRING_CAST=true'));
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('A ist AnsiString; ausdrückliche Umwandlung in string (wie W1059).', mFound[1].Message);
  mFound := Findings(mSource, TArray<string>.Create('IMPLICIT_STRING_CAST=error'));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[0].Severity));
  Assert.AreEqual('', Messages(Findings(mSource, TArray<string>.Create('WARNINGS=false'))));
  Assert.AreEqual(1, Integer(Length(Findings(Routine('{$WARN IMPLICIT_STRING_CAST ON}'#10, '  S: string;'#10 +
    '  A: AnsiString;'#10, '  S := A;'#10), TArray<string>.Create('IMPLICIT_STRING_CAST=false')))));
end;

procedure TStringConversionTests.SilentCases;
begin
  // Gegenfälle, die dcc ohne Meldung übersetzt, und unsichere Typen.
  Assert.AreEqual('', Messages(Findings(Routine('', '  S, T: string;'#10'  A, B: AnsiString;'#10 +
    '  W: WideString;'#10'  C: Char;'#10'  K: AnsiChar;'#10'  P: PAnsiChar;'#10'  Ok: Boolean;'#10 +
    '  {$IFDEF ANSI}'#10'  Wechselnd: AnsiString;'#10'  {$ELSE}'#10'  Wechselnd: string;'#10'  {$ENDIF}'#10,
    '  S := T;'#10'  A := B;'#10'  A := ''abc'';'#10'  S := W;'#10'  W := S;'#10'  S := S + A;'#10 +
    '  S := string(A);'#10'  S := Unbekannt;'#10'  A := Unbekannt;'#10'  S := Wechselnd;'#10'  S := P;'#10 +
    '  Ok := K in [''a''..''z''];'#10'  Ok := C in Ziffern;'#10'  Ok := C in [Trenner, ''x''];'#10 +
    '  Ok := CharInSet(C, [''a'']);'#10'  S[1] := ''x'';'#10'  A := #$20AC;'#10))));
  // Ein einfacher Alias ist derselbe Typ; ein Codepage-String ist ein eigener Typ: keine Aussage.
  Assert.AreEqual('T ist AnsiString; die Zuweisung an S wandelt implizit um (wie W1057). | ', Messages(Findings(
    'unit Texte;'#10'interface'#10'type'#10'  TText = AnsiString;'#10'  TLatin = type AnsiString(28591);'#10 +
    'implementation'#10'procedure Pruefen(T: TText; L: TLatin; S: string);'#10'begin'#10'  S := T;'#10 +
    '  S := L;'#10'end;'#10'end.')));
  // {$H-}: string ist ShortString.
  Assert.AreEqual('', Messages(Findings(Routine('{$H-}'#10, '  S: string;'#10'  A: AnsiString;'#10,
    '  S := A;'#10))));
  Assert.AreEqual('', Messages(Findings(Routine('{$LONGSTRINGS OFF}'#10, '  S: string;'#10'  A: AnsiString;'#10,
    '  S := A;'#10))));
end;

procedure TStringConversionTests.ConversionTable;
begin
  Assert.AreEqual(Ord(TStringTypeKind.Unicode), Ord(TStringConversionRule.KindOf('System.UnicodeString')));
  Assert.AreEqual(Ord(TStringTypeKind.Ansi), Ord(TStringConversionRule.KindOf('rawbytestring')));
  Assert.AreEqual(Ord(TStringTypeKind.Utf8), Ord(TStringConversionRule.KindOf('UTF8String')));
  Assert.AreEqual(Ord(TStringTypeKind.None), Ord(TStringConversionRule.KindOf('ShortString')));
  Assert.AreEqual('W1057', TStringConversionRule.ConversionCode(TStringTypeKind.Ansi, TStringTypeKind.Unicode, False));
  Assert.AreEqual('W1058', TStringConversionRule.ConversionCode(TStringTypeKind.Unicode, TStringTypeKind.Ansi, False));
  Assert.AreEqual('W1059', TStringConversionRule.ConversionCode(TStringTypeKind.Ansi, TStringTypeKind.Unicode, True));
  Assert.AreEqual('W1060', TStringConversionRule.ConversionCode(TStringTypeKind.Unicode, TStringTypeKind.Ansi, True));
  Assert.AreEqual('W1057', TStringConversionRule.ConversionCode(TStringTypeKind.Unicode, TStringTypeKind.Utf8, False));
  Assert.AreEqual('', TStringConversionRule.ConversionCode(TStringTypeKind.Utf8, TStringTypeKind.Ansi, False));
  Assert.AreEqual('', TStringConversionRule.ConversionCode(TStringTypeKind.Unicode, TStringTypeKind.Unicode, False));
  Assert.AreEqual('', TStringConversionRule.ConversionCode(TStringTypeKind.None, TStringTypeKind.Ansi, False));
  Assert.IsTrue(TStringConversionRule.LostIn1252(#$2603));
  Assert.IsTrue(TStringConversionRule.LostIn1252(#$D83D));
  Assert.IsFalse(TStringConversionRule.LostIn1252(#$20AC));
  Assert.IsFalse(TStringConversionRule.LostIn1252(#$0100));
  Assert.IsFalse(TStringConversionRule.LostIn1252('a'));
end;

procedure TStringConversionTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Routine('', '  S: string;'#10'  A: AnsiString;'#10, '  S := A;'#10);
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '', 'Source/Texte.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"string-conversion": "off"}}',
    'Source/Texte.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": "off"}}', 'Source/Texte.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource,
    '{"rules": {"string-conversion": {"exclude": ["Source/*.pas"]}}}', 'Source/Texte.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TStringConversionTests);

end.
