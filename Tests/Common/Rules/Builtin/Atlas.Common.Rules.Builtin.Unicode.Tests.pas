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
    procedure ConfusableSkipsIdentifierWithQuote;
  end;

  /// <summary>Ungültiges UTF-8, Formulare und Zeichenkodierung der Datei.</summary>
  [TestFixture]
  TUnicodeEncodingRuleTests = class
  public
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
    [Test]
    procedure Utf32FileIsReportedOnce;
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
  cFormUnit = 'unit Form1;'#13#10'interface'#13#10'type'#13#10'  TForm1 = class(TForm)'#13#10 +
    '    Button1: TButton;'#13#10'  end;'#13#10'implementation'#13#10'end.';

/// <summary>Prüfung mit Formulardatei und Dateien; AFiles: Name → Bytes.</summary>
function Run(const ARule: IRule; const ASource, AFormText: string; const AUnitBytes, AFormBytes: TBytes;
  const AConfig: string): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := TServerSettings.Default;
  if AConfig <> '' then
  begin
    mSettings := TConfigurationParser.Parse(AConfig, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'Form1.pas';
    mContext.UnitName := 'Form1';
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.FormText := AFormText;
    if AFormText <> '' then
    begin
      mContext.FormFile := 'C:\P\Form1.dfm';
    end;
    mContext.ReadFile :=
      function(const AName: string; out AData: TBytes): Boolean
      begin
        Result := True;
        if SameText(AName, 'Form1.pas') and (AUnitBytes <> nil) then
        begin
          AData := AUnitBytes;
        end
        else if SameText(AName, 'Form1.dfm') and (AFormBytes <> nil) then
        begin
          AData := AFormBytes;
        end
        else
        begin
          Result := False;
        end;
      end;
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

function Apply(const AText: string; const AEdit: TTextEdit): string;
var
  mTable: TLineTable;
  mStart, mStop: Integer;
begin
  mTable := TLineTable.Build(AText);
  mStart := mTable.OffsetAt(AEdit.Range.StartPos);
  mStop := mTable.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, mStart) + AEdit.NewText + Copy(AText, mStop + 1, MaxInt);
end;

function Bytes(const AValues: array of Byte): TBytes;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    Result[mIndex] := AValues[mIndex];
  end;
end;

{ TUnicodeRuleTests }

procedure TUnicodeRuleTests.BidiControlInCommentReported;
begin
  TRuleAssert.Reports(TBidiControlRule.Create, UnitWith('// Zugriff ' + Char($202E) + ' { ' + Char($2066) + ' }'), 2);
end;

procedure TUnicodeRuleTests.BidiControlPosition;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TBidiControlRule.Create, UnitWith('const S = ''a' + Char($202E) + 'b'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
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
  mFindings: TArray<TRuleFinding>;
begin
  // "Pаssword" mit kyrillischem а (U+0430)
  mFindings := TRuleAssert.Findings(TConfusableIdentifierRule.Create,
    UnitWith('var P' + Char($0430) + 'ssword: Integer;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TUnicodeRuleTests.UmlautIdentifierHiddenByDefault;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, UnitWith('var Größe: Integer;'));
end;

procedure TUnicodeRuleTests.UmlautIdentifierShownWithLowThreshold;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var Größe: Integer;'),
    '{ "minConfidence": "low" }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
end;

procedure TUnicodeRuleTests.AsciiIdentifierSilent;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, UnitWith('var Password: Integer;'));
end;

procedure TUnicodeRuleTests.RegistersAllRules;
var
  mRegistry: TRuleRegistry;
  mRule: IRule;
begin
  mRegistry := TRuleRegistry.Create;
  try
    RegisterUnicodeRules(mRegistry);
    Assert.AreEqual(5, Integer(Length(mRegistry.Rules)));
    Assert.IsTrue(mRegistry.Find('file-encoding-unsupported', mRule));
    Assert.IsTrue(mRegistry.Find('bidi-control', mRule));
    Assert.IsTrue(mRegistry.Find('confusable-identifier', mRule));
  finally
    mRegistry.Free;
  end;
end;

procedure TUnicodeRuleTests.HebrewWithRtlMarkIsNoError;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := UnitWith('const S = ''' + Char($05E9) + Char($05DC) + Char($05D5) + Char($05DD) + Char($200F) +
    ' 1'';');
  TRuleAssert.Silent(TBidiControlRule.Create, mSource);
  mFindings := TRuleAssert.Findings(TBidiControlRule.Create, mSource, '{ "minConfidence": "low" }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
end;

procedure TUnicodeRuleTests.UnclosedOverrideInCommentIsError;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TBidiControlRule.Create, UnitWith('{ Admin ' + Char($202E) + ' } X := 1;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TInvisibleCharRule.Create, UnitWith('const S = ''a' +
    StringOfChar(Char($200B), 50) + 'b'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(62, mFindings[0].Range.EndPos.Character);
  Assert.Contains(mFindings[0].Message, '50 Zeichen U+200B');
end;

procedure TUnicodeRuleTests.InvisibleInStringIsMediumOutsideHigh;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TInvisibleCharRule.Create, UnitWith('const S = ''a' + Char($200D) + 'b'';'));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  mFindings := TRuleAssert.Findings(TInvisibleCharRule.Create, UnitWith('const S' + Char($200B) + ' = 1;'));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TUnicodeRuleTests.GreekLetterIsMediumCyrillicLookalikeHigh;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var Winkel' + Char($03B1) +
    ': Integer;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  mFindings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var D' + Char($0430) +
    'ten: Integer;'));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TUnicodeRuleTests.ConfusableFixUsesLatinLetters;
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  mSource := UnitWith('var P' + Char($0430) + 'ssw' + Char($043E) + 'rd: Integer;');
  mFindings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Password', mFindings[0].Fixes[0].Edits[0].NewText);
  // Mehrdeutig (Griechisch ohne Gegenstück): keine Korrektur.
  mFindings := TRuleAssert.Findings(TConfusableIdentifierRule.Create, UnitWith('var Winkel' + Char($03B1) +
    ': Integer;'));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TUnicodeRuleTests.StringFixWritesCharLiteralAndParses;
var
  mFindings: TArray<TRuleFinding>;
  mSource, mFixed: string;
  mTree: TSyntaxTree;
begin
  mSource := UnitWith('const S = ''a' + Char($200B) + 'b'';');
  mFindings := TRuleAssert.Findings(TInvisibleCharRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  mFixed := Apply(mSource, mFindings[0].Fixes[0].Edits[0]);
  Assert.AreEqual(UnitWith('const S = ''a''#$200B''b'';'), mFixed);
  mTree := TPascalParser.Parse(mFixed);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
  // Am Anfang des Strings: ''#$200B'b' ist ebenso gültig.
  mSource := UnitWith('const S = ''' + Char($200B) + 'b'';');
  mFixed := Apply(mSource, TRuleAssert.Findings(TInvisibleCharRule.Create, mSource)[0].Fixes[0].Edits[0]);
  mTree := TPascalParser.Parse(mFixed);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
end;

procedure TUnicodeRuleTests.FixOutsideStringRemovesCharacter;
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  mSource := UnitWith('// Hinweis ' + Char($202E) + 'x');
  mFindings := TRuleAssert.Findings(TBidiControlRule.Create, mSource);
  Assert.AreEqual(UnitWith('// Hinweis x'), Apply(mSource, mFindings[0].Fixes[0].Edits[0]));
  Assert.IsFalse(mFindings[0].Fixes[0].Safe);
end;

procedure TUnicodeEncodingRuleTests.FormCharCodeIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Run(TBidiControlRule.Create, cFormUnit, 'object Form1: TForm1'#13#10 +
    '  object Button1: TButton'#13#10'    Caption = ''A''#8238''B'''#13#10'  end'#13#10'end', nil, nil, '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Zeile 3 (Button1.Caption)');
  Assert.Contains(mFindings[0].Message, 'U+202E');
  // Gemeldet am Feld Button1 in der Unit.
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
end;

procedure TUnicodeEncodingRuleTests.FormRawCharGetsFormFix;
var
  mFindings: TArray<TRuleFinding>;
  mForm: string;
begin
  mForm := 'object Form1: TForm1'#13#10'  Caption = ''A' + Char($200B) + 'B'''#13#10'end';
  mFindings := Run(TInvisibleCharRule.Create, cFormUnit, mForm, nil, nil, '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('C:\P\Form1.dfm', mFindings[0].Fixes[0].FileName);
  Assert.AreEqual('object Form1: TForm1'#13#10'  Caption = ''A''#8203''B'''#13#10'end',
    Apply(mForm, mFindings[0].Fixes[0].Edits[0]));
  // Gemeldet an der Formularklasse.
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
end;

procedure TUnicodeEncodingRuleTests.InvalidUtf8ByteHasLineAndColumn;
var
  mData: TBytes;
  mSource: string;
  mFormat: TFileFormat;
  mFindings: TArray<TRuleFinding>;
begin
  // BOM, "unit U;" CRLF "// a" $FF "b": Zeile 1, Spalte 4. Den Text liefert der Dekodierer (Delphi U+FFFD).
  mData := Bytes([$EF, $BB, $BF, Ord('u'), Ord('n'), Ord('i'), Ord('t'), Ord(' '), Ord('U'), Ord(';'), 13, 10,
    Ord('/'), Ord('/'), Ord(' '), Ord('a'), $FF, Ord('b'), 13, 10, Ord('i'), Ord('m'), Ord('p'), Ord('l'), Ord('e'),
    Ord('m'), Ord('e'), Ord('n'), Ord('t'), Ord('a'), Ord('t'), Ord('i'), Ord('o'), Ord('n'), 13, 10, Ord('e'),
    Ord('n'), Ord('d'), Ord('.')]);
  mSource := TFileEncoding.Decode(mData, mFormat);
  Assert.AreEqual(1, Integer(Length(TFileEncoding.InvalidUtf8(mData, mFormat))), 'Fehlstellen');
  mFindings := Run(TControlCharRule.Create, mSource, '', mData, nil, '');
  Assert.AreEqual(1, Integer(Length(mFindings)), 'Datei');
  Assert.AreEqual(1, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Character);
  Assert.Contains(mFindings[0].Message, '$FF');
  // Geänderter Puffer: die Stellen der Datei gelten nicht, dann nur U+FFFD; im Kommentar übersetzt dcc es (#1327).
  mFindings := Run(TControlCharRule.Create, 'unit U;'#13#10'// xa' + Char($FFFD) + 'b', '', mData, nil, '');
  Assert.AreEqual(0, Integer(Length(mFindings)), 'Kommentar');
  mFindings := Run(TControlCharRule.Create, 'unit U;'#13#10'var xa' + Char($FFFD) + 'b', '', mData, nil, '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'U+FFFD');
end;

procedure TUnicodeEncodingRuleTests.InvalidUtf8InAnsiLookingUtf8File;
var
  mData: TBytes;
  mSource: string;
  mFormat: TFileFormat;
  mFindings: TArray<TRuleFinding>;
begin
  // Ohne BOM: gültiges "ä" und "ö" (C3 A4, C3 B6) und ein einzelnes $FF; Atlas liest die Datei als ANSI.
  // Die gültigen Folgen überwiegen: beschädigtes UTF-8 (#1327).
  mData := Bytes([Ord('/'), Ord('/'), Ord(' '), $C3, $A4, $C3, $B6, Ord(' '), $FF, 13, 10, Ord('u'), Ord('n'),
    Ord('i'), Ord('t'), Ord(' '), Ord('U'), Ord(';')]);
  mSource := TFileEncoding.Decode(mData, mFormat);
  mFindings := Run(TControlCharRule.Create, mSource, '', mData, nil, '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Character);
end;

procedure TUnicodeEncodingRuleTests.PlainAnsiFileIsNoInvalidUtf8;
var
  mData: TBytes;
  mSource: string;
  mFormat: TFileFormat;
begin
  // Echtes ANSI ("ä" als $E4) ist kein beschädigtes UTF-8.
  mData := Bytes([Ord('/'), Ord('/'), Ord(' '), $E4, 13, 10, Ord('u'), Ord('n'), Ord('i'), Ord('t'), Ord(' '),
    Ord('U'), Ord(';')]);
  mSource := TFileEncoding.Decode(mData, mFormat);
  Assert.AreEqual(0, Integer(Length(Run(TControlCharRule.Create, mSource, '', mData, nil, ''))));
end;

procedure TUnicodeEncodingRuleTests.InvalidUtf8InForm;
var
  mData: TBytes;
  mForm: string;
  mFormat: TFileFormat;
  mFindings: TArray<TRuleFinding>;
begin
  mData := Bytes([$EF, $BB, $BF, Ord('o'), Ord('b'), Ord('j'), Ord('e'), Ord('c'), Ord('t'), Ord(' '), Ord('F'),
    Ord('o'), Ord('r'), Ord('m'), Ord('1'), Ord(':'), Ord(' '), Ord('T'), Ord('F'), Ord('o'), Ord('r'), Ord('m'),
    Ord('1'), 13, 10, Ord(' '), Ord(' '), Ord('C'), Ord('a'), Ord('p'), Ord('t'), Ord('i'), Ord('o'), Ord('n'),
    Ord(' '), Ord('='), Ord(' '), Ord(''''), $E2, $82, Ord(''''), 13, 10, Ord('e'), Ord('n'), Ord('d')]);
  mForm := TFileEncoding.Decode(mData, mFormat);
  mFindings := Run(TControlCharRule.Create, cFormUnit, mForm, nil, mData, '');
  Assert.AreEqual(1, Integer(Length(mFindings)), mForm);
  Assert.Contains(mFindings[0].Message, 'Zeile 2, Spalte 14');
end;

/// <summary>Bytes von F15_AnsiDatei.pas: Windows-1252 mit "ü", "ß", "ö", "ä" und "°" als UTF-8 (C2 B0).</summary>
function F15Bytes: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('unit F15_AnsiDatei;'#13#10'// Gr') + Bytes([$FC, $DF]) +
    TEncoding.ASCII.GetBytes('e aus K') + Bytes([$F6]) + TEncoding.ASCII.GetBytes('ln, Zeichen ') +
    Bytes([$C2, $B0]) + TEncoding.ASCII.GetBytes(' '#13#10'interface'#13#10'const S = ''') + Bytes([$E4, $F6, $FC]) +
    TEncoding.ASCII.GetBytes(''';'#13#10'implementation'#13#10'end.'#13#10);
end;

procedure TUnicodeEncodingRuleTests.AnsiFileWithStrayUtf8PairIsSilent;
var
  mData: TBytes;
  mSource: string;
  mFormat: TFileFormat;
begin
  mData := F15Bytes;
  mSource := TFileEncoding.Decode(mData, mFormat);
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Ansi1252, mFormat.Encoding, 'Kodierung');
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
  Assert.AreEqual<TFileEncodingKind>(TFileEncodingKind.Utf8, mFormat.Encoding, 'Kodierung');
  Assert.AreEqual(0, Integer(Length(Run(TControlCharRule.Create, mSource, '', mData, nil, ''))));
  TRuleAssert.Silent(TControlCharRule.Create, UnitWith('{ a' + Char($FFFD) + ' }'#13#10'(* ' + Char($FFFD) + ' *)'));
end;

procedure TUnicodeRuleTests.ReplacementCharInStringIsHint;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TControlCharRule.Create, UnitWith('const S = ''a' + Char($FFFD) + 'b'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, mFindings[0].Severity, 'Schweregrad');
  // Mit einem echten Steuerzeichen daneben bleibt es ein Fehler.
  mFindings := TRuleAssert.Findings(TControlCharRule.Create, UnitWith('const S = ''a' + Char($FFFD) + #1'b'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mFindings[0].Severity, 'Schweregrad mit Steuerzeichen');
end;

procedure TUnicodeRuleTests.ReplacementCharInCodeIsError;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TControlCharRule.Create, UnitWith('var X' + Char($FFFD) + ': Integer;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mFindings[0].Severity, 'Schweregrad');
end;

{ file-encoding-unsupported (#1085) }

function Routine(const AStatement: string): string;
begin
  Result := UnitWith('procedure P;'#13#10'var'#13#10'  Titel: string;'#13#10'begin'#13#10'  ' + AStatement +
    #13#10'end;');
end;

procedure TUnicodeRuleTests.TypographicQuotesBecomeString;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine('Titel := ' + Char($201A) + 'Bericht' + Char($2018) + ';');
  mFindings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Typografische Anführungszeichen sind im Quelltext nicht erlaubt (wie E2038).', mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(20, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  mFixed := Apply(mSource, mFindings[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Routine('Titel := ''Bericht'';'), mFixed);
  TRuleAssert.Silent(TFileEncodingUnsupportedRule.Create, mFixed);
end;

procedure TUnicodeRuleTests.GermanQuotesKeepApostropheInside;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // „Peter’s Bericht“: das ’ gehört in den String, das Paar ist „ … “.
  mSource := Routine('Titel := ' + Char($201E) + 'Peter' + Char($2019) + 's Bericht' + Char($201C) + ';');
  mFindings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Routine('Titel := ''Peter' + Char($2019) + 's Bericht'';'),
    Apply(mSource, mFindings[0].Fixes[0].Edits[0]));
end;

procedure TUnicodeRuleTests.DoubleQuotesBecomeString;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine('Titel := "Bericht";');
  mFindings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Doppelte');
  Assert.AreEqual(Routine('Titel := ''Bericht'';'), Apply(mSource, mFindings[0].Fixes[0].Edits[0]));
end;

procedure TUnicodeRuleTests.QuoteWithStringInsideHasNoFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  // "Don't": im Zitat beginnt ein String; ihn umzubauen änderte die Bedeutung.
  mFindings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create,
    Routine('Titel := ' + Char($201C) + 'a'' + ''b' + Char($201D) + ';'));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TUnicodeRuleTests.DashGetsAsciiFixQuestionMarkNone;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine('Titel := IntToStr(4 ' + Char($2013) + ' 2) ?;');
  mFindings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Zeichen ''' + Char($2013) + ''' (#$2013) ist im Quelltext nicht erlaubt (wie E2038).',
    mFindings[0].Message);
  Assert.AreEqual(Routine('Titel := IntToStr(4 - 2) ?;'), Apply(mSource, mFindings[0].Fixes[0].Edits[0]));
  Assert.Contains(mFindings[1].Message, '''?''');
  Assert.AreEqual(0, Integer(Length(mFindings[1].Fixes)));
end;

procedure TUnicodeRuleTests.EmojiIsOneFinding;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TFileEncodingUnsupportedRule.Create,
    Routine('Titel := ''a''; ' + Char($D83D) + Char($DE00)));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, '#$1F600');
  Assert.AreEqual(2, mFindings[0].Range.EndPos.Character - mFindings[0].Range.StartPos.Character);
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

procedure TUnicodeEncodingRuleTests.Utf32FileIsReportedOnce;
var
  mData: TBytes;
  mSource: string;
  mFormat: TFileFormat;
  mFindings: TArray<TRuleFinding>;
begin
  mData := Bytes([$FF, $FE, 0, 0, Ord('u'), 0, 0, 0, Ord('n'), 0, 0, 0, Ord('i'), 0, 0, 0, Ord('t'), 0, 0, 0]);
  mSource := TFileEncoding.Decode(mData, mFormat);
  mFindings := Run(TFileEncodingUnsupportedRule.Create, mSource, '', mData, nil, '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'F2438');
  Assert.AreEqual(0, mFindings[0].Range.StartPos.Line);
  // Die NUL des falsch dekodierten Textes sind Folgefehler, control-char schweigt.
  Assert.AreEqual(0, Integer(Length(Run(TControlCharRule.Create, mSource, '', mData, nil, ''))));
  // UTF-8 ist in Ordnung.
  mData := TEncoding.UTF8.GetBytes(UnitWith(''));
  Assert.AreEqual(0, Integer(Length(Run(TFileEncodingUnsupportedRule.Create, UnitWith(''), '', mData, nil, ''))));
end;

procedure TUnicodeRuleTests.ConfusableSkipsIdentifierWithQuote;
begin
  TRuleAssert.Silent(TConfusableIdentifierRule.Create, Routine('Titel := ' + Char($201A) + 'Bericht' +
    Char($2018) + ';'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnicodeRuleTests);
  TDUnitX.RegisterTestFixture(TUnicodeEncodingRuleTests);

end.
