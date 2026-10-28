unit Atlas.Common.Rules.Builtin.Unicode.Tests;

// Tests für die Unicode-Regeln (#150): je Regel positive und negative Fälle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnicodeRuleTests = class
  public
    [Test]
    procedure BidiControlInCommentReported;
    [Test]
    procedure BidiControlPosition;
    [Test]
    procedure PlainCodeHasNoBidiControl;
    [Test]
    procedure ZeroWidthSpaceReported;
    [Test]
    procedure LeadingBomIsAllowed;
    [Test]
    procedure NulAndReplacementCharReported;
    [Test]
    procedure TabsAndLineBreaksAreFine;
    [Test]
    procedure MixedScriptIdentifierReported;
    [Test]
    procedure UmlautIdentifierHiddenByDefault;
    [Test]
    procedure UmlautIdentifierShownWithLowThreshold;
    [Test]
    procedure AsciiIdentifierSilent;
    [Test]
    procedure RegistersAllRules;
    [Test]
    procedure HebrewWithRtlMarkIsNoError;
    [Test]
    procedure UnclosedOverrideInCommentIsError;
    [Test]
    procedure BalancedEmbeddingInRtlStringIsLow;
    [Test]
    procedure FiftyZeroWidthSpacesAreOneFinding;
    [Test]
    procedure InvisibleInStringIsMediumOutsideHigh;
    [Test]
    procedure GreekLetterIsMediumCyrillicLookalikeHigh;
    [Test]
    procedure ConfusableFixUsesLatinLetters;
    [Test]
    procedure StringFixWritesCharLiteralAndParses;
    [Test]
    procedure FixOutsideStringRemovesCharacter;
    [Test]
    procedure FormCharCodeIsReported;
    [Test]
    procedure FormRawCharGetsFormFix;
    [Test]
    procedure InvalidUtf8ByteHasLineAndColumn;
    [Test]
    procedure InvalidUtf8InAnsiLookingUtf8File;
    [Test]
    procedure PlainAnsiFileIsNoInvalidUtf8;
    [Test]
    procedure InvalidUtf8InForm;
    /// <summary>Minimalfall F15 (#1327): ANSI mit Umlauten und einem zufällig gültigen UTF-8-Paar.</summary>
    [Test]
    procedure AnsiFileWithStrayUtf8PairIsSilent;
    /// <summary>Minimalfall F16 (#1327): gültiges UTF-8 mit U+FFFD im Kommentar.</summary>
    [Test]
    procedure ReplacementCharInCommentIsSilent;
    [Test]
    procedure ReplacementCharInStringIsHint;
    [Test]
    procedure ReplacementCharInCodeIsError;
    [Test]
    procedure TypographicQuotesBecomeString;
    [Test]
    procedure GermanQuotesKeepApostropheInside;
    [Test]
    procedure DoubleQuotesBecomeString;
    [Test]
    procedure QuoteWithStringInsideHasNoFix;
    [Test]
    procedure DashGetsAsciiFixQuestionMarkNone;
    [Test]
    procedure EmojiIsOneFinding;
    [Test]
    procedure StringsCommentsAndLettersAreAllowed;
    [Test]
    procedure ConditionalBranchAndAsmAreSkipped;
    [Test]
    procedure Utf32FileIsReportedOnce;
    [Test]
    procedure ConfusableSkipsIdentifierWithQuote;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Unicode,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Text.Lines,
  Atlas.Tests.RuleAssert;

function UnitWith(const ABody: string): string;
begin
  Result := 'unit U;'#13#10'interface'#13#10'implementation'#13#10 + ABody + #13#10'end.';
end;

const
  FormUnit = 'unit Form1;'#13#10'interface'#13#10'type'#13#10'  TForm1 = class(TForm)'#13#10 +
    '    Button1: TButton;'#13#10'  end;'#13#10'implementation'#13#10'end.';

/// <summary>Prüfung mit Formulardatei und Dateien; AFiles: Name → Bytes.</summary>
function Run(const ARule: IRule; const ASource, AFormText: string; const AUnitBytes, AFormBytes: TBytes;
  const AConfig: string): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := TServerSettings.Default;
  if AConfig <> '' then
    Settings := TConfigurationParser.Parse(AConfig, Issues);
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := 'Form1.pas';
    Context.UnitName := 'Form1';
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.FormText := AFormText;
    if AFormText <> '' then
      Context.FormFile := 'C:\P\Form1.dfm';
    Context.ReadFile :=
      function(const AName: string; out AData: TBytes): Boolean
      begin
        Result := True;
        if SameText(AName, 'Form1.pas') and (AUnitBytes <> nil) then
          AData := AUnitBytes
        else if SameText(AName, 'Form1.dfm') and (AFormBytes <> nil) then
          AData := AFormBytes
        else
          Result := False;
      end;
    Result := TRuleEngine.Run([ARule], Settings, Context);
  finally
    Tree.Free;
  end;
end;

function Apply(const AText: string; const AEdit: TTextEdit): string;
var
  Table: TLineTable;
  Start, Stop: Integer;
begin
  Table := TLineTable.Build(AText);
  Start := Table.OffsetAt(AEdit.Range.StartPos);
  Stop := Table.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, Start) + AEdit.NewText + Copy(AText, Stop + 1, MaxInt);
end;

function Bytes(const AValues: array of Byte): TBytes;
var
  Index: Integer;
begin
  SetLength(Result, Length(AValues));
  for Index := 0 to High(AValues) do
    Result[Index] := AValues[Index];
end;

{ TUnicodeRuleTests }

procedure TUnicodeRuleTests.BidiControlInCommentReported;
begin
  TRuleAssert.Reports(TBidiControlRule.Create, UnitWith('// Zugriff ' + Char($202E) + ' { ' + Char($2066) + ' }'), 2);
end;

procedure TUnicodeRuleTests.BidiControlPosition;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TBidiControlRule.Create, UnitWith('const S = ''a' + Char($202E) + 'b'';'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
end;

procedure TUnicodeRuleTests.PlainCodeHasNoBidiControl;
begin
  TRuleAssert.Silent(TBidiControlRule.Create, UnitWith('const S = ''Größe: äöü'';'));
end;

procedure TUnicodeRuleTests.ZeroWidthSpaceReported;
begin
  TRuleAssert.Reports(TInvisibleCharRule.Create, UnitWith('const S = ''a' + Char($200B) + 'b'';'));
end;

procedure TUnicodeRuleTests.LeadingBomIsAllowed;
begin
  TRuleAssert.Silent(TInvisibleCharRule.Create, Char($FEFF) + UnitWith(''));
end;

procedure TUnicodeRuleTests.NulAndReplacementCharReported;
begin
  // NUL im Kommentar und U+FFFD im Code; U+FFFD im Kommentar übersetzt dcc (#1327).
  TRuleAssert.Reports(TControlCharRule.Create, UnitWith('// a'#0'b'#13#10'var X' + Char($FFFD) + ': Integer;'), 2);
end;

procedure TUnicodeRuleTests.TabsAndLineBreaksAreFine;
begin
  TRuleAssert.Silent(TControlCharRule.Create, UnitWith(#9'// Tab'#10'// LF'#12));
end;

procedure TUnicodeRuleTests.MixedScriptIdentifierReported;
var
  Findings: TArray<TRuleFinding>;
begin
  // "Pаssword" mit kyrillischem а (U+0430)
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create,
    UnitWith('var P' + Char($0430) + 'ssword: Integer;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TUnicodeRuleTests.UmlautIdentifierHiddenByDefault;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, UnitWith('var Größe: Integer;'));
end;

procedure TUnicodeRuleTests.UmlautIdentifierShownWithLowThreshold;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var Größe: Integer;'),
    '{ "minConfidence": "low" }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
end;

procedure TUnicodeRuleTests.AsciiIdentifierSilent;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, UnitWith('var Password: Integer;'));
end;

procedure TUnicodeRuleTests.RegistersAllRules;
var
  Registry: TRuleRegistry;
  Rule: IRule;
begin
  Registry := TRuleRegistry.Create;
  try
    RegisterUnicodeRules(Registry);
    Assert.AreEqual(5, Integer(Length(Registry.Rules)));
    Assert.IsTrue(Registry.Find('file-encoding-unsupported', Rule));
    Assert.IsTrue(Registry.Find('bidi-control', Rule));
    Assert.IsTrue(Registry.Find('confusable-identifier', Rule));
  finally
    Registry.Free;
  end;
end;

procedure TUnicodeRuleTests.HebrewWithRtlMarkIsNoError;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := UnitWith('const S = ''' + Char($05E9) + Char($05DC) + Char($05D5) + Char($05DD) + Char($200F) +
    ' 1'';');
  TRuleAssert.Silent(TBidiControlRule.Create, Source);
  Findings := TRuleAssert.Findings(TBidiControlRule.Create, Source, '{ "minConfidence": "low" }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
end;

procedure TUnicodeRuleTests.UnclosedOverrideInCommentIsError;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TBidiControlRule.Create, UnitWith('{ Admin ' + Char($202E) + ' } X := 1;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TUnicodeRuleTests.BalancedEmbeddingInRtlStringIsLow;
begin
  // Hebräisch mit geschlossenem RLE … PDF im selben String: legitim.
  TRuleAssert.Silent(TBidiControlRule.Create, UnitWith('const S = ''' + Char($202B) + Char($05E9) + Char($05DC) +
    Char($202C) + ''';'));
  // Ohne RTL-Schrift bleibt es ein Fehler.
  TRuleAssert.Reports(TBidiControlRule.Create, UnitWith('const S = ''' + Char($202B) + 'abc' + Char($202C) + ''';'), 2);
end;

procedure TUnicodeRuleTests.FiftyZeroWidthSpacesAreOneFinding;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TInvisibleCharRule.Create, UnitWith('const S = ''a' +
    StringOfChar(Char($200B), 50) + 'b'';'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(12, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(62, Findings[0].Range.EndPos.Character);
  Assert.Contains(Findings[0].Message, '50 Zeichen U+200B');
end;

procedure TUnicodeRuleTests.InvisibleInStringIsMediumOutsideHigh;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TInvisibleCharRule.Create, UnitWith('const S = ''a' + Char($200D) + 'b'';'));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Findings := TRuleAssert.Findings(TInvisibleCharRule.Create, UnitWith('const S' + Char($200B) + ' = 1;'));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TUnicodeRuleTests.GreekLetterIsMediumCyrillicLookalikeHigh;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var Winkel' + Char($03B1) +
    ': Integer;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var D' + Char($0430) +
    'ten: Integer;'));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TUnicodeRuleTests.ConfusableFixUsesLatinLetters;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  Source := UnitWith('var P' + Char($0430) + 'ssw' + Char($043E) + 'rd: Integer;');
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Password', Findings[0].Fixes[0].Edits[0].NewText);
  // Mehrdeutig (Griechisch ohne Gegenstück): keine Korrektur.
  Findings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var Winkel' + Char($03B1) +
    ': Integer;'));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TUnicodeRuleTests.StringFixWritesCharLiteralAndParses;
var
  Findings: TArray<TRuleFinding>;
  Source, Fixed: string;
  Tree: TSyntaxTree;
begin
  Source := UnitWith('const S = ''a' + Char($200B) + 'b'';');
  Findings := TRuleAssert.Findings(TInvisibleCharRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Fixed := Apply(Source, Findings[0].Fixes[0].Edits[0]);
  Assert.AreEqual(UnitWith('const S = ''a''#$200B''b'';'), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  // Am Anfang des Strings: ''#$200B'b' ist ebenso gültig.
  Source := UnitWith('const S = ''' + Char($200B) + 'b'';');
  Fixed := Apply(Source, TRuleAssert.Findings(TInvisibleCharRule.Create, Source)[0].Fixes[0].Edits[0]);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
end;

procedure TUnicodeRuleTests.FixOutsideStringRemovesCharacter;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  Source := UnitWith('// Hinweis ' + Char($202E) + 'x');
  Findings := TRuleAssert.Findings(TBidiControlRule.Create, Source);
  Assert.AreEqual(UnitWith('// Hinweis x'), Apply(Source, Findings[0].Fixes[0].Edits[0]));
  Assert.IsFalse(Findings[0].Fixes[0].Safe);
end;

procedure TUnicodeRuleTests.FormCharCodeIsReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(TBidiControlRule.Create, FormUnit, 'object Form1: TForm1'#13#10 +
    '  object Button1: TButton'#13#10'    Caption = ''A''#8238''B'''#13#10'  end'#13#10'end', nil, nil, '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'Zeile 3 (Button1.Caption)');
  Assert.Contains(Findings[0].Message, 'U+202E');
  // Gemeldet am Feld Button1 in der Unit.
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
end;

procedure TUnicodeRuleTests.FormRawCharGetsFormFix;
var
  Findings: TArray<TRuleFinding>;
  Form: string;
begin
  Form := 'object Form1: TForm1'#13#10'  Caption = ''A' + Char($200B) + 'B'''#13#10'end';
  Findings := Run(TInvisibleCharRule.Create, FormUnit, Form, nil, nil, '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('C:\P\Form1.dfm', Findings[0].Fixes[0].FileName);
  Assert.AreEqual('object Form1: TForm1'#13#10'  Caption = ''A''#8203''B'''#13#10'end',
    Apply(Form, Findings[0].Fixes[0].Edits[0]));
  // Gemeldet an der Formularklasse.
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
end;

procedure TUnicodeRuleTests.InvalidUtf8ByteHasLineAndColumn;
var
  Data: TBytes;
  Source: string;
  Format: TFileFormat;
  Findings: TArray<TRuleFinding>;
begin
  // BOM, "unit U;" CRLF "// a" $FF "b": Zeile 1, Spalte 4. Den Text liefert der Dekodierer (Delphi U+FFFD).
  Data := Bytes([$EF, $BB, $BF, Ord('u'), Ord('n'), Ord('i'), Ord('t'), Ord(' '), Ord('U'), Ord(';'), 13, 10,
    Ord('/'), Ord('/'), Ord(' '), Ord('a'), $FF, Ord('b'), 13, 10, Ord('i'), Ord('m'), Ord('p'), Ord('l'), Ord('e'),
    Ord('m'), Ord('e'), Ord('n'), Ord('t'), Ord('a'), Ord('t'), Ord('i'), Ord('o'), Ord('n'), 13, 10, Ord('e'),
    Ord('n'), Ord('d'), Ord('.')]);
  Source := TFileEncoding.Decode(Data, Format);
  Assert.AreEqual(1, Integer(Length(TFileEncoding.InvalidUtf8(Data, Format))), 'Fehlstellen');
  Findings := Run(TControlCharRule.Create, Source, '', Data, nil, '');
  Assert.AreEqual(1, Integer(Length(Findings)), 'Datei');
  Assert.AreEqual(1, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Character);
  Assert.Contains(Findings[0].Message, '$FF');
  // Geänderter Puffer: die Stellen der Datei gelten nicht, dann nur U+FFFD; im Kommentar übersetzt dcc es (#1327).
  Findings := Run(TControlCharRule.Create, 'unit U;'#13#10'// xa' + Char($FFFD) + 'b', '', Data, nil, '');
  Assert.AreEqual(0, Integer(Length(Findings)), 'Kommentar');
  Findings := Run(TControlCharRule.Create, 'unit U;'#13#10'var xa' + Char($FFFD) + 'b', '', Data, nil, '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'U+FFFD');
end;

procedure TUnicodeRuleTests.InvalidUtf8InAnsiLookingUtf8File;
var
  Data: TBytes;
  Source: string;
  Format: TFileFormat;
  Findings: TArray<TRuleFinding>;
begin
  // Ohne BOM: gültiges "ä" und "ö" (C3 A4, C3 B6) und ein einzelnes $FF; Atlas liest die Datei als ANSI.
  // Die gültigen Folgen überwiegen: beschädigtes UTF-8 (#1327).
  Data := Bytes([Ord('/'), Ord('/'), Ord(' '), $C3, $A4, $C3, $B6, Ord(' '), $FF, 13, 10, Ord('u'), Ord('n'),
    Ord('i'), Ord('t'), Ord(' '), Ord('U'), Ord(';')]);
  Source := TFileEncoding.Decode(Data, Format);
  Findings := Run(TControlCharRule.Create, Source, '', Data, nil, '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(8, Findings[0].Range.StartPos.Character);
end;

procedure TUnicodeRuleTests.PlainAnsiFileIsNoInvalidUtf8;
var
  Data: TBytes;
  Source: string;
  Format: TFileFormat;
begin
  // Echtes ANSI ("ä" als $E4) ist kein beschädigtes UTF-8.
  Data := Bytes([Ord('/'), Ord('/'), Ord(' '), $E4, 13, 10, Ord('u'), Ord('n'), Ord('i'), Ord('t'), Ord(' '),
    Ord('U'), Ord(';')]);
  Source := TFileEncoding.Decode(Data, Format);
  Assert.AreEqual(0, Integer(Length(Run(TControlCharRule.Create, Source, '', Data, nil, ''))));
end;

procedure TUnicodeRuleTests.InvalidUtf8InForm;
var
  Data: TBytes;
  Form: string;
  Format: TFileFormat;
  Findings: TArray<TRuleFinding>;
begin
  Data := Bytes([$EF, $BB, $BF, Ord('o'), Ord('b'), Ord('j'), Ord('e'), Ord('c'), Ord('t'), Ord(' '), Ord('F'),
    Ord('o'), Ord('r'), Ord('m'), Ord('1'), Ord(':'), Ord(' '), Ord('T'), Ord('F'), Ord('o'), Ord('r'), Ord('m'),
    Ord('1'), 13, 10, Ord(' '), Ord(' '), Ord('C'), Ord('a'), Ord('p'), Ord('t'), Ord('i'), Ord('o'), Ord('n'),
    Ord(' '), Ord('='), Ord(' '), Ord(''''), $E2, $82, Ord(''''), 13, 10, Ord('e'), Ord('n'), Ord('d')]);
  Form := TFileEncoding.Decode(Data, Format);
  Findings := Run(TControlCharRule.Create, FormUnit, Form, nil, Data, '');
  Assert.AreEqual(1, Integer(Length(Findings)), Form);
  Assert.Contains(Findings[0].Message, 'Zeile 2, Spalte 14');
end;

/// <summary>Bytes von F15_AnsiDatei.pas: Windows-1252 mit "ü", "ß", "ö", "ä" und "°" als UTF-8 (C2 B0).</summary>
function F15Bytes: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('unit F15_AnsiDatei;'#13#10'// Gr') + Bytes([$FC, $DF]) +
    TEncoding.ASCII.GetBytes('e aus K') + Bytes([$F6]) + TEncoding.ASCII.GetBytes('ln, Zeichen ') +
    Bytes([$C2, $B0]) + TEncoding.ASCII.GetBytes(' '#13#10'interface'#13#10'const S = ''') + Bytes([$E4, $F6, $FC]) +
    TEncoding.ASCII.GetBytes(''';'#13#10'implementation'#13#10'end.'#13#10);
end;

procedure TUnicodeRuleTests.AnsiFileWithStrayUtf8PairIsSilent;
var
  mData: TBytes;
  mSource: string;
  mFormat: TFileFormat;
begin
  mData := F15Bytes;
  mSource := TFileEncoding.Decode(mData, mFormat);
  Assert.IsTrue(mFormat.Encoding = TFileEncodingKind.Ansi1252, 'Kodierung');
  Assert.AreEqual(0, Integer(Length(Run(TControlCharRule.Create, mSource, '', mData, nil, ''))));
end;

procedure TUnicodeRuleTests.ReplacementCharInCommentIsSilent;
var
  mData: TBytes;
  mSource: string;
  mFormat: TFileFormat;
begin
  // F16_Ersatzzeichen.pas: zwei U+FFFD (EF BF BD) in einem Kommentar, sonst ASCII, ohne BOM.
  mData := TEncoding.ASCII.GetBytes('unit F16_Ersatzzeichen;'#13#10'// Kommentar mit ') +
    Bytes([$EF, $BF, $BD, $EF, $BF, $BD]) +
    TEncoding.ASCII.GetBytes(' im Text'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10);
  mSource := TFileEncoding.Decode(mData, mFormat);
  Assert.IsTrue(mFormat.Encoding = TFileEncodingKind.Utf8, 'Kodierung');
  Assert.AreEqual(0, Integer(Length(Run(TControlCharRule.Create, mSource, '', mData, nil, ''))));
  TRuleAssert.Silent(TControlCharRule.Create, UnitWith('{ a' + Char($FFFD) + ' }'#13#10'(* ' + Char($FFFD) + ' *)'));
end;

procedure TUnicodeRuleTests.ReplacementCharInStringIsHint;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TControlCharRule.Create, UnitWith('const S = ''a' + Char($FFFD) + 'b'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(mFindings[0].Severity = TRuleSeverity.Hint, 'Schweregrad');
  // Mit einem echten Steuerzeichen daneben bleibt es ein Fehler.
  mFindings := TRuleAssert.Findings(TControlCharRule.Create, UnitWith('const S = ''a' + Char($FFFD) + #1'b'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(mFindings[0].Severity = TRuleSeverity.Error, 'Schweregrad mit Steuerzeichen');
end;

procedure TUnicodeRuleTests.ReplacementCharInCodeIsError;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TControlCharRule.Create, UnitWith('var X' + Char($FFFD) + ': Integer;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(mFindings[0].Severity = TRuleSeverity.Error, 'Schweregrad');
end;

{ file-encoding-unsupported (#1085) }

function Routine(const AStatement: string): string;
begin
  Result := UnitWith('procedure P;'#13#10'var'#13#10'  Titel: string;'#13#10'begin'#13#10'  ' + AStatement +
    #13#10'end;');
end;

procedure TUnicodeRuleTests.TypographicQuotesBecomeString;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Routine('Titel := ' + Char($201A) + 'Bericht' + Char($2018) + ';');
  Findings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Typografische Anführungszeichen sind im Quelltext nicht erlaubt (wie E2038).', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(20, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Fixed := Apply(Source, Findings[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Routine('Titel := ''Bericht'';'), Fixed);
  TRuleAssert.Silent(TFileEncodingUnsupportedRule.Create, Fixed);
end;

procedure TUnicodeRuleTests.GermanQuotesKeepApostropheInside;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // „Peter’s Bericht“: das ’ gehört in den String, das Paar ist „ … “.
  Source := Routine('Titel := ' + Char($201E) + 'Peter' + Char($2019) + 's Bericht' + Char($201C) + ';');
  Findings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Routine('Titel := ''Peter' + Char($2019) + 's Bericht'';'),
    Apply(Source, Findings[0].Fixes[0].Edits[0]));
end;

procedure TUnicodeRuleTests.DoubleQuotesBecomeString;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Routine('Titel := "Bericht";');
  Findings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'Doppelte');
  Assert.AreEqual(Routine('Titel := ''Bericht'';'), Apply(Source, Findings[0].Fixes[0].Edits[0]));
end;

procedure TUnicodeRuleTests.QuoteWithStringInsideHasNoFix;
var
  Findings: TArray<TRuleFinding>;
begin
  // "Don't": im Zitat beginnt ein String; ihn umzubauen änderte die Bedeutung.
  Findings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create,
    Routine('Titel := ' + Char($201C) + 'a'' + ''b' + Char($201D) + ';'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TUnicodeRuleTests.DashGetsAsciiFixQuestionMarkNone;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Routine('Titel := IntToStr(4 ' + Char($2013) + ' 2) ?;');
  Findings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Zeichen ''' + Char($2013) + ''' (#$2013) ist im Quelltext nicht erlaubt (wie E2038).',
    Findings[0].Message);
  Assert.AreEqual(Routine('Titel := IntToStr(4 - 2) ?;'), Apply(Source, Findings[0].Fixes[0].Edits[0]));
  Assert.Contains(Findings[1].Message, '''?''');
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
end;

procedure TUnicodeRuleTests.EmojiIsOneFinding;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create,
    Routine('Titel := ''a''; ' + Char($D83D) + Char($DE00)));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, '#$1F600');
  Assert.AreEqual(2, Findings[0].Range.EndPos.Character - Findings[0].Range.StartPos.Character);
end;

procedure TUnicodeRuleTests.StringsCommentsAndLettersAreAllowed;
begin
  TRuleAssert.Silent(TFileEncodingUnsupportedRule.Create, Routine('Titel := ''' + Char($201E) + 'x' +
    Char($201C) + ' ' + Char($2013) + ' ? "y"''; // ' + Char($201A) + 'z' + Char($2018) + ' ?'#13#10 +
    '  { ' + Char($00AB) + ' } Gr' + Char($00F6) + Char($00DF) + 'e := 1; ' + Char($03BB) + ' := 2; Wert' +
    Char($203F) + 'X := 3;'));
end;

procedure TUnicodeRuleTests.ConditionalBranchAndAsmAreSkipped;
begin
  TRuleAssert.Silent(TFileEncodingUnsupportedRule.Create, UnitWith('procedure P;'#13#10'begin'#13#10 +
    '  {$IFDEF FPC} Titel := ' + Char($201A) + 'a' + Char($2018) + '; {$ENDIF}'#13#10 +
    '  asm'#13#10'    db "x"'#13#10'  end;'#13#10'end;'));
end;

procedure TUnicodeRuleTests.Utf32FileIsReportedOnce;
var
  Data: TBytes;
  Source: string;
  Format: TFileFormat;
  Findings: TArray<TRuleFinding>;
begin
  Data := Bytes([$FF, $FE, 0, 0, Ord('u'), 0, 0, 0, Ord('n'), 0, 0, 0, Ord('i'), 0, 0, 0, Ord('t'), 0, 0, 0]);
  Source := TFileEncoding.Decode(Data, Format);
  Findings := Run(TFileEncodingUnsupportedRule.Create, Source, '', Data, nil, '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'F2438');
  Assert.AreEqual(0, Findings[0].Range.StartPos.Line);
  // Die NUL des falsch dekodierten Textes sind Folgefehler, control-char schweigt.
  Assert.AreEqual(0, Integer(Length(Run(TControlCharRule.Create, Source, '', Data, nil, ''))));
  // UTF-8 ist in Ordnung.
  Data := TEncoding.UTF8.GetBytes(UnitWith(''));
  Assert.AreEqual(0, Integer(Length(Run(TFileEncodingUnsupportedRule.Create, UnitWith(''), '', Data, nil, ''))));
end;

procedure TUnicodeRuleTests.ConfusableSkipsIdentifierWithQuote;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, Routine('Titel := ' + Char($201A) + 'Bericht' +
    Char($2018) + ';'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnicodeRuleTests);

end.
