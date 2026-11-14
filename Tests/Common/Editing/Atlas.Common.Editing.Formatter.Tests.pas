unit Atlas.Common.Editing.Formatter.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract;

type
  [TestFixture]
  TFormatterTests = class
  private
    function Formatted(const AText: string; const ASettings: TFormatStyle): string;
  public
    [Test]
    procedure TrimsTrailingWhitespace;
    [Test]
    procedure ConvertsIndentation;
    [Test]
    procedure SpacesAssignmentsAndCommas;
    [Test]
    procedure ChangesKeywordCase;
    [Test]
    procedure KeepsCommentsStringsAndAsm;
    [Test]
    procedure ChangesLineEndingsAndFinalNewline;
    [Test]
    procedure FormatsOnlyRange;
    /// <summary>Ein abschließender Umbruch ist eine leere letzte Zeile (TTextLines.SplitLines): kein zweiter
    /// Umbruch, und beim Wechsel der Zeilenenden bleibt er erhalten.</summary>
    [Test]
    procedure KeepsSingleFinalNewline;
    [Test]
    procedure FormatsEmptyText;
    [Test]
    procedure LeavesFormattedCodeAlone;
    /// <summary>#1358: Zeilen von "atlas-format: off" bis "on" bleiben samt der Marken unverändert, in jeder
    /// Kommentarform; ohne "on" bis zum Dateiende.</summary>
    [Test]
    procedure KeepsProtectedRegions;
    /// <summary>#1358: Eine geschützte Zeile verhindert auch, dass begin an sie angehängt wird.</summary>
    [Test]
    procedure ProtectedLineIsNotJoined;
  end;

  [TestFixture]
  TEditorConfigTests = class
  public
    [Test]
    procedure MatchesSectionPatterns;
    [Test]
    procedure AppliesMatchingSections;
    [Test]
    procedure NearerFilesWinUntilRoot;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Editing.EditorConfig;

{ TFormatterTests }

function TFormatterTests.Formatted(const AText: string; const ASettings: TFormatStyle): string;
begin
  Result := TFormatter.FormatText(AText, TPascalLexer.Tokenize(AText), ASettings);
end;

procedure TFormatterTests.TrimsTrailingWhitespace;
begin
  Assert.AreEqual('begin'#10'  A := 1;'#10'end.',
    Formatted('begin   '#10'  A := 1;'#9#10'end.', TFormatStyle.Default));
end;

procedure TFormatterTests.ConvertsIndentation;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  // Ohne Neueinrückung nach der Blockstruktur: Tab = eine Ebene mit indentSize Leerzeichen.
  mSettings.Reindent := False;
  Assert.AreEqual('begin'#10'  A := 1;'#10'    B := 2;'#10'end.',
    Formatted('begin'#10#9'A := 1;'#10#9#9'B := 2;'#10'end.', mSettings));
  mSettings.UseTabs := True;
  mSettings.IndentSize := 4;
  Assert.AreEqual('begin'#10#9'A := 1;'#10#9'  B := 2;'#10'end.',
    Formatted('begin'#10'    A := 1;'#10'      B := 2;'#10'end.', mSettings));
end;

procedure TFormatterTests.SpacesAssignmentsAndCommas;
begin
  Assert.AreEqual('begin'#10'  A := F(1, 2, { x } 3);'#10'end.',
    Formatted('begin'#10'  A:=F(1,2,  { x } 3);'#10'end.', TFormatStyle.Default));
  // Zeilenumbruch nach := bleibt.
  Assert.AreEqual('begin'#10'  A :='#10'    1;'#10'end.',
    Formatted('begin'#10'  A:='#10'    1;'#10'end.', TFormatStyle.Default));
end;

procedure TFormatterTests.ChangesKeywordCase;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  Assert.AreEqual('BEGIN'#10'  Begin_ := ''Begin'';'#10'End.', Formatted('BEGIN'#10'  Begin_ := ''Begin'';'#10'End.', mSettings));
  mSettings.KeywordCase := TKeywordCase.Lower;
  Assert.AreEqual('begin'#10'  Begin_ := ''Begin'';'#10'end.', Formatted('BEGIN'#10'  Begin_ := ''Begin'';'#10'End.', mSettings));
  mSettings.KeywordCase := TKeywordCase.Upper;
  Assert.AreEqual('BEGIN'#10'  X := 1;'#10'END.', Formatted('begin'#10'  X := 1;'#10'end.', mSettings));
end;

procedure TFormatterTests.KeepsCommentsStringsAndAsm;
const
  cText =
    'procedure P;'#10 +
    '{ Kommentar   '#10 +
    '      eingerückt   '#10 +
    '}'#10 +
    'asm'#10 +
    '        MOV   EAX,1   '#10 +
    'end;';
begin
  Assert.AreEqual(cText, Formatted(cText, TFormatStyle.Default));
end;

procedure TFormatterTests.ChangesLineEndingsAndFinalNewline;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.EndOfLine := #13#10;
  mSettings.InsertFinalNewline := True;
  Assert.AreEqual('begin'#13#10'end.'#13#10, Formatted('begin'#10'end.', mSettings));
  mSettings.EndOfLine := '';
  Assert.AreEqual('begin'#10'end.'#10, Formatted('begin'#10'end.', mSettings));
end;

procedure TFormatterTests.KeepsSingleFinalNewline;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.InsertFinalNewline := True;
  Assert.AreEqual('begin'#10'end.'#10, Formatted('begin'#10'end.'#10, mSettings));
  mSettings.EndOfLine := #13#10;
  Assert.AreEqual('begin'#13#10'end.'#13#10, Formatted('begin'#10'end.'#10, mSettings));
  Assert.AreEqual('begin'#13#10'end.'#13#10, Formatted('begin'#13'end.'#13, mSettings));
end;

procedure TFormatterTests.FormatsEmptyText;
begin
  Assert.AreEqual('', Formatted('', TFormatStyle.Default));
end;

procedure TFormatterTests.FormatsOnlyRange;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  mText := 'begin'#10'  A:=1;'#10'  B:=2;'#10'end.';
  mEdits := TFormatter.Edits(mText, TPascalLexer.Tokenize(mText), TFormatStyle.Default, 2, 2);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(2, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual('  B := 2;', mEdits[0].NewText);
end;

procedure TFormatterTests.LeavesFormattedCodeAlone;
var
  mText: string;
begin
  mText := 'unit U;'#10'interface'#10'implementation'#10'procedure P(A, B: Integer);'#10'begin'#10 +
    '  A := B;'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(TFormatter.Edits(mText, TPascalLexer.Tokenize(mText), TFormatStyle.Default))));
end;

{ TEditorConfigTests }

procedure TEditorConfigTests.MatchesSectionPatterns;
begin
  Assert.IsTrue(TEditorConfig.Matches('*', 'Unit1.pas'));
  Assert.IsTrue(TEditorConfig.Matches('*.pas', 'Unit1.PAS'));
  Assert.IsTrue(TEditorConfig.Matches('*.{pas,dpr}', 'Projekt.dpr'));
  Assert.IsTrue(TEditorConfig.Matches('src/*.pas', 'Unit1.pas'));
  Assert.IsFalse(TEditorConfig.Matches('*.dfm', 'Unit1.pas'));
  Assert.IsFalse(TEditorConfig.Matches('*.{dfm,fmx}', 'Unit1.pas'));
end;

procedure TEditorConfigTests.AppliesMatchingSections;
var
  mSettings: TFormatStyle;
  mRoot: Boolean;
begin
  mSettings := TFormatStyle.Default;
  TEditorConfig.Apply(
    'root = true'#10 +
    '[*]'#10 +
    'indent_style = tab'#10 +
    'tab_width = 4'#10 +
    'end_of_line = crlf'#10 +
    '[*.dfm]'#10 +
    'indent_style = space'#10 +
    '[*.pas]'#10 +
    'trim_trailing_whitespace = false'#10 +
    'insert_final_newline = true'#10 +
    'max_line_length = 100'#10, 'C:\P\Unit1.pas', mSettings, mRoot);
  Assert.IsTrue(mRoot);
  Assert.IsTrue(mSettings.UseTabs);
  Assert.AreEqual(4, mSettings.IndentSize);
  Assert.AreEqual(#13#10, mSettings.EndOfLine);
  Assert.IsFalse(mSettings.TrimTrailingWhitespace);
  Assert.IsTrue(mSettings.InsertFinalNewline);
  Assert.AreEqual(100, mSettings.MaxLineLength);
  TEditorConfig.Apply('[*]'#10'max_line_length = off'#10, 'C:\P\Unit1.pas', mSettings, mRoot);
  Assert.AreEqual(0, mSettings.MaxLineLength);
end;

procedure TEditorConfigTests.NearerFilesWinUntilRoot;
var
  mFiles: TDictionary<string, string>;
  mSettings: TFormatStyle;
begin
  mFiles := TDictionary<string, string>.Create;
  try
    mFiles.Add('c:\.editorconfig', '[*]'#10'indent_size = 8'#10'end_of_line = lf');
    mFiles.Add('c:\p\.editorconfig', 'root = true'#10'[*]'#10'indent_size = 3');
    mFiles.Add('c:\p\sub\.editorconfig', '[*.pas]'#10'indent_style = tab');
    mSettings := TEditorConfig.ForFile('C:\P\Sub\Unit1.pas',
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := mFiles.TryGetValue(LowerCase(AFileName), AText);
      end, TFormatStyle.Default);
    Assert.AreEqual(3, mSettings.IndentSize);
    Assert.IsTrue(mSettings.UseTabs);
    // Oberhalb von root = true wird nichts gelesen.
    Assert.AreEqual('', mSettings.EndOfLine);
  finally
    mFiles.Free;
  end;
end;

procedure TFormatterTests.KeepsProtectedRegions;
begin
  Assert.AreEqual('begin'#10'  // atlas-format: off'#10'      A:=1;'#10'  // atlas-format: on'#10'  B := 2;'#10'end.',
    Formatted('begin'#10'  // atlas-format: off'#10'      A:=1;'#10'  // atlas-format: on'#10'   B:=2;'#10'end.',
    TFormatStyle.Default));
  Assert.AreEqual('begin'#10'  {Atlas-Format:OFF}'#10'      A:=1;'#10'  (* atlas-format: on *)'#10'  B := 2;'#10'end.',
    Formatted('begin'#10'  {Atlas-Format:OFF}'#10'      A:=1;'#10'  (* atlas-format: on *)'#10'      B:=2;'#10'end.',
    TFormatStyle.Default));
  // Ohne "on": bis zum Ende, davor wird formatiert.
  Assert.AreEqual('begin'#10'  A := 1;'#10'    // atlas-format: off'#10'      B:=2;'#10'end.',
    Formatted('begin'#10'    A:=1;'#10'    // atlas-format: off'#10'      B:=2;'#10'end.', TFormatStyle.Default));
end;

procedure TFormatterTests.ProtectedLineIsNotJoined;
var
  mSettings: TFormatStyle;
  mText: string;
begin
  mSettings := TFormatStyle.Default;
  mSettings.BeginPlacement := TBlockPlacement.SameLine;
  mText := 'procedure P;'#10'begin'#10'  if A then // atlas-format: off'#10'  begin'#10'  end; // atlas-format: on'#10 +
    'end;';
  Assert.AreEqual(mText, Formatted(mText, mSettings));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatterTests);
  TDUnitX.RegisterTestFixture(TEditorConfigTests);

end.
