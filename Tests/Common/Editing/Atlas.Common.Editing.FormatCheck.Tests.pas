unit Atlas.Common.Editing.FormatCheck.Tests;

// Tests für das Formatieren ohne Editor (#1358): Abweichungen je Zeile mit Art
// und Text, Bereiche für geänderte Zeilen (übrige Zeilen bleiben gleich),
// Syntaxfehler, Stabilität und die Stabilität über das Referenzprojekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormatCheckTests = class
  public
    [Test]
    procedure FormattedTextHasNoDeviation;
    [Test]
    procedure DescribesIndentation;
    [Test]
    procedure DescribesSpacesAndCase;
    [Test]
    procedure DescribesTrailingWhitespaceAndFinalNewline;
    [Test]
    procedure DescribesLineEndings;
    [Test]
    procedure DescribesLineBreaks;
    /// <summary>Wie „Dokument formatieren“: dasselbe Ergebnis wie TFormatter.FormatText.</summary>
    [Test]
    procedure WholeFileMatchesFormatter;
    /// <summary>Nur die Zeilen der Bereiche ändern sich, die übrigen bleiben Zeichen für Zeichen gleich, auch ihre
    /// Zeilenumbrüche.</summary>
    [Test]
    procedure SpansKeepOtherLines;
    [Test]
    procedure AdjacentSpansMerge;
    [Test]
    procedure EmptySpansChangeNothing;
    [Test]
    procedure SyntaxErrorKeepsText;
    [Test]
    procedure ResultIsStable;
    /// <summary>Zweimal formatieren ergibt dasselbe für alle Dateien des Referenzprojekts (#94), mit Vorgaben
    /// und mit allen Schaltern.</summary>
    [Test]
    procedure ReferenceProjectIsStable;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Editing.FormatCheck;

function Kinds(const ADeviations: TArray<TFormatDeviation>): string;
var
  mDeviation: TFormatDeviation;
begin
  Result := '';
  for mDeviation in ADeviations do
  begin
    if Result <> '' then
      Result := Result + ' | ';
    Result := Result + Format('%d %s: %s', [mDeviation.Line + 1, TFormatCheck.KindName(mDeviation.Kind),
      mDeviation.Message]);
  end;
end;

function DeviationsOf(const AText: string; const AStyle: TFormatStyle): string;
begin
  Result := Kinds(TFormatCheck.Deviations(AText, TFormatCheck.FormatText(AText, AStyle, TFormatScope.All), AStyle));
end;

function NoDefines: TPreprocessorOptions;
begin
  Result := Default(TPreprocessorOptions);
end;

{ TFormatCheckTests }

procedure TFormatCheckTests.FormattedTextHasNoDeviation;
const
  cText = 'procedure P;'#10'begin'#10'  A := F(1, 2);'#10'end;';
var
  mOutcome: TFormatOutcome;
begin
  mOutcome := TFormatCheck.Run(cText, TFormatStyle.Default, TFormatScope.All, NoDefines);
  Assert.IsFalse(mOutcome.Changed);
  Assert.IsFalse(mOutcome.HasSyntaxError);
  Assert.IsTrue(mOutcome.Stable);
  Assert.AreEqual(0, Integer(Length(mOutcome.Deviations)));
end;

procedure TFormatCheckTests.DescribesIndentation;
var
  mStyle: TFormatStyle;
begin
  Assert.AreEqual('3 indent: Einrückung 3 statt 2',
    DeviationsOf('procedure P;'#10'begin'#10'   A := 1;'#10'end;', TFormatStyle.Default));
  mStyle := TFormatStyle.Default;
  mStyle.Reindent := False;
  Assert.AreEqual('3 indentChars: Einrückung mit Tabulator statt Leerzeichen',
    DeviationsOf('procedure P;'#10'begin'#10#9'A := 1;'#10'end;', mStyle));
end;

procedure TFormatCheckTests.DescribesSpacesAndCase;
var
  mStyle: TFormatStyle;
begin
  Assert.AreEqual('3 spaceAroundAssignment: Leerzeichen nach := fehlt | ' +
    '3 spaceAroundAssignment: Leerzeichen vor := fehlt | 3 spaceAfterComma: Leerzeichen nach Komma fehlt',
    DeviationsOf('procedure P;'#10'begin'#10'  A:=F(1,2);'#10'end;', TFormatStyle.Default));
  Assert.AreEqual('3 spaceAroundAssignment: Zu viele Leerzeichen vor :=',
    DeviationsOf('procedure P;'#10'begin'#10'  A   := 1;'#10'end;', TFormatStyle.Default));
  mStyle := TFormatStyle.Default;
  mStyle.KeywordCase := TKeywordCase.Lower;
  Assert.AreEqual('2 keywordCase: Schreibweise `Begin`',
    DeviationsOf('procedure P;'#10'Begin'#10'  A := 1;'#10'end;', mStyle));
end;

procedure TFormatCheckTests.DescribesTrailingWhitespaceAndFinalNewline;
var
  mStyle: TFormatStyle;
begin
  Assert.AreEqual('1 trailingWhitespace: Leerzeichen am Zeilenende',
    DeviationsOf('procedure P;  '#10'begin'#10'end;', TFormatStyle.Default));
  mStyle := TFormatStyle.Default;
  mStyle.InsertFinalNewline := True;
  Assert.AreEqual('3 finalNewline: Zeilenumbruch am Dateiende fehlt',
    DeviationsOf('procedure P;'#10'begin'#10'end;', mStyle));
end;

procedure TFormatCheckTests.DescribesLineEndings;
var
  mStyle: TFormatStyle;
begin
  mStyle := TFormatStyle.Default;
  mStyle.EndOfLine := #13#10;
  Assert.AreEqual('1 endOfLine: Zeilenenden LF statt CRLF', DeviationsOf('procedure P;'#10'begin'#10'end;', mStyle));
end;

procedure TFormatCheckTests.DescribesLineBreaks;
var
  mStyle: TFormatStyle;
begin
  mStyle := TFormatStyle.Default;
  mStyle.BeginPlacement := TBlockPlacement.SameLine;
  Assert.AreEqual('3 lineBreaks: Zeilenumbruch: 2 Zeilen statt 1',
    DeviationsOf('procedure P;'#10'begin'#10'  if A then'#10'  begin'#10'  end;'#10'end;', mStyle));
end;

procedure TFormatCheckTests.WholeFileMatchesFormatter;
const
  cText = 'procedure P;  '#13#10'begin'#13#10'     A:=F(1,2);'#13#10'end;';
var
  mStyle: TFormatStyle;
begin
  mStyle := TFormatStyle.Default;
  Assert.AreEqual(TFormatter.FormatText(cText, TPascalLexer.Tokenize(cText), mStyle),
    TFormatCheck.FormatText(cText, mStyle, TFormatScope.All));
  mStyle.EndOfLine := #10;
  mStyle.InsertFinalNewline := True;
  mStyle.KeywordCase := TKeywordCase.Upper;
  Assert.AreEqual(TFormatter.FormatText(cText, TPascalLexer.Tokenize(cText), mStyle),
    TFormatCheck.FormatText(cText, mStyle, TFormatScope.All));
end;

procedure TFormatCheckTests.SpansKeepOtherLines;
const
  // Gemischte Zeilenumbrüche: Die Zeilen außerhalb behalten ihre.
  cText = 'procedure P;'#13#10'begin'#10'     A:=1;'#13#10'     B:=2;'#10'     C:=3;'#13#10'end;';
var
  mFormatted: string;
begin
  mFormatted := TFormatCheck.FormatText(cText, TFormatStyle.Default,
    TFormatScope.Lines([TFormatLineSpan.Create(3, 3)]));
  Assert.AreEqual('procedure P;'#13#10'begin'#10'     A:=1;'#13#10'  B := 2;'#10'     C:=3;'#13#10'end;', mFormatted);
  mFormatted := TFormatCheck.FormatText(cText, TFormatStyle.Default,
    TFormatScope.Lines([TFormatLineSpan.Create(4, 4), TFormatLineSpan.Create(2, 2)]));
  Assert.AreEqual('procedure P;'#13#10'begin'#10'  A := 1;'#13#10'     B:=2;'#10'  C := 3;'#13#10'end;', mFormatted);
end;

procedure TFormatCheckTests.AdjacentSpansMerge;
const
  cText = 'procedure P;'#10'begin'#10'     A:=1;'#10'     B:=2;'#10'end;';
begin
  Assert.AreEqual('procedure P;'#10'begin'#10'  A := 1;'#10'  B := 2;'#10'end;',
    TFormatCheck.FormatText(cText, TFormatStyle.Default,
    TFormatScope.Lines([TFormatLineSpan.Create(3, 3), TFormatLineSpan.Create(2, 2), TFormatLineSpan.Create(2, 3)])));
end;

procedure TFormatCheckTests.EmptySpansChangeNothing;
const
  cText = 'procedure P;'#10'begin'#10'     A:=1;'#10'end;';
var
  mOutcome: TFormatOutcome;
begin
  mOutcome := TFormatCheck.Run(cText, TFormatStyle.Default, TFormatScope.Lines(nil), NoDefines);
  Assert.IsFalse(mOutcome.Changed);
  Assert.IsTrue(mOutcome.Stable);
end;

procedure TFormatCheckTests.SyntaxErrorKeepsText;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'     A:=1'#10'  if then;'#10 +
    'end;'#10'end.';
var
  mOutcome: TFormatOutcome;
begin
  mOutcome := TFormatCheck.Run(cText, TFormatStyle.Default, TFormatScope.All, NoDefines);
  Assert.IsTrue(mOutcome.HasSyntaxError);
  Assert.IsFalse(mOutcome.Changed);
  Assert.AreEqual(cText, mOutcome.Formatted);
  Assert.AreEqual(0, Integer(Length(mOutcome.Deviations)));
end;

procedure TFormatCheckTests.ResultIsStable;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'if A then'#10'begin'#10 +
    'B:=1; // b'#10'Count:=2; // c'#10'end'#10'else'#10'begin'#10'end;'#10'end;'#10'end.';
var
  mStyle: TFormatStyle;
  mOutcome: TFormatOutcome;
begin
  mStyle := TFormatStyle.Default;
  mStyle.BeginPlacement := TBlockPlacement.SameLine;
  mStyle.ElsePlacement := TBlockPlacement.SameLine;
  mStyle.AlignAssignments := True;
  mStyle.AlignComments := True;
  mStyle.KeywordCase := TKeywordCase.Lower;
  mOutcome := TFormatCheck.Run(cText, mStyle, TFormatScope.All, NoDefines);
  Assert.IsFalse(mOutcome.HasSyntaxError);
  Assert.IsTrue(mOutcome.Changed);
  Assert.IsTrue(mOutcome.Stable);
  Assert.AreEqual(mOutcome.Formatted, TFormatCheck.FormatText(mOutcome.Formatted, mStyle, TFormatScope.All));
end;

/// <summary>Ordner des Referenzprojekts, gesucht von der Test-EXE aufwärts; '' ohne.</summary>
function ReferenceFolder: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
      Exit;
    if ExtractFileDir(mDirectory) = mDirectory then
      Break;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

procedure TFormatCheckTests.ReferenceProjectIsStable;
var
  mFolder, mFileName, mText, mOnce, mUnstable: string;
  mFormat: TFileFormat;
  mStyles: TArray<TFormatStyle>;
  mStyle: TFormatStyle;
  mCount: Integer;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden');
    Exit;
  end;
  mStyle := TFormatStyle.Default;
  mStyles := [mStyle];
  mStyle.KeywordCase := TKeywordCase.Lower;
  mStyle.BeginPlacement := TBlockPlacement.NewLine;
  mStyle.ElsePlacement := TBlockPlacement.SameLine;
  mStyle.AlignAssignments := True;
  mStyle.AlignDeclarations := True;
  mStyle.AlignComments := True;
  mStyle.MaxLineLength := 100;
  mStyle.InsertFinalNewline := True;
  mStyle.EndOfLine := #13#10;
  mStyles := mStyles + [mStyle];
  mUnstable := '';
  mCount := 0;
  for mFileName in TDirectory.GetFiles(mFolder, '*.pas', TSearchOption.soAllDirectories) do
  begin
    mText := TFileEncoding.Decode(TFile.ReadAllBytes(mFileName), mFormat);
    Inc(mCount);
    for mStyle in mStyles do
    begin
      mOnce := TFormatCheck.FormatText(mText, mStyle, TFormatScope.All);
      if TFormatCheck.FormatText(mOnce, mStyle, TFormatScope.All) <> mOnce then
        mUnstable := mUnstable + ' ' + ExtractFileName(mFileName);
    end;
  end;
  Assert.IsTrue(mCount > 0, 'keine Units im Referenzprojekt');
  Assert.AreEqual('', mUnstable, 'nicht stabil formatiert:');
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatCheckTests);

end.
