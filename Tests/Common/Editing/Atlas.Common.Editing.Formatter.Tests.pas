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
    /// Umbruch, und beim Wechsel der Zeilenenden bleibt er erhalten (D-03).</summary>
    [Test]
    procedure KeepsSingleFinalNewline;
    [Test]
    procedure FormatsEmptyText;
    [Test]
    procedure LeavesFormattedCodeAlone;
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
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  // Tab = eine Ebene mit indentSize Leerzeichen.
  Assert.AreEqual('begin'#10'  A := 1;'#10'    B := 2;'#10'end.',
    Formatted('begin'#10#9'A := 1;'#10#9#9'B := 2;'#10'end.', Settings));
  Settings.UseTabs := True;
  Settings.IndentSize := 4;
  Assert.AreEqual('begin'#10#9'A := 1;'#10#9'  B := 2;'#10'end.',
    Formatted('begin'#10'    A := 1;'#10'      B := 2;'#10'end.', Settings));
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
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Assert.AreEqual('BEGIN'#10'  Begin_ := ''Begin'';'#10'End.', Formatted('BEGIN'#10'  Begin_ := ''Begin'';'#10'End.', Settings));
  Settings.KeywordCase := TKeywordCase.Lower;
  Assert.AreEqual('begin'#10'  Begin_ := ''Begin'';'#10'end.', Formatted('BEGIN'#10'  Begin_ := ''Begin'';'#10'End.', Settings));
  Settings.KeywordCase := TKeywordCase.Upper;
  Assert.AreEqual('BEGIN'#10'  X := 1;'#10'END.', Formatted('begin'#10'  X := 1;'#10'end.', Settings));
end;

procedure TFormatterTests.KeepsCommentsStringsAndAsm;
const
  Text =
    'procedure P;'#10 +
    '{ Kommentar   '#10 +
    '      eingerückt   '#10 +
    '}'#10 +
    'asm'#10 +
    '        MOV   EAX,1   '#10 +
    'end;';
begin
  Assert.AreEqual(Text, Formatted(Text, TFormatStyle.Default));
end;

procedure TFormatterTests.ChangesLineEndingsAndFinalNewline;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.EndOfLine := #13#10;
  Settings.InsertFinalNewline := True;
  Assert.AreEqual('begin'#13#10'end.'#13#10, Formatted('begin'#10'end.', Settings));
  Settings.EndOfLine := '';
  Assert.AreEqual('begin'#10'end.'#10, Formatted('begin'#10'end.', Settings));
end;

procedure TFormatterTests.KeepsSingleFinalNewline;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.InsertFinalNewline := True;
  Assert.AreEqual('begin'#10'end.'#10, Formatted('begin'#10'end.'#10, Settings));
  Settings.EndOfLine := #13#10;
  Assert.AreEqual('begin'#13#10'end.'#13#10, Formatted('begin'#10'end.'#10, Settings));
  Assert.AreEqual('begin'#13#10'end.'#13#10, Formatted('begin'#13'end.'#13, Settings));
end;

procedure TFormatterTests.FormatsEmptyText;
begin
  Assert.AreEqual('', Formatted('', TFormatStyle.Default));
end;

procedure TFormatterTests.FormatsOnlyRange;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Text := 'begin'#10'  A:=1;'#10'  B:=2;'#10'end.';
  Edits := TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), TFormatStyle.Default, 2, 2);
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(2, Edits[0].Range.StartPos.Line);
  Assert.AreEqual('  B := 2;', Edits[0].NewText);
end;

procedure TFormatterTests.LeavesFormattedCodeAlone;
var
  Text: string;
begin
  Text := 'unit U;'#10'interface'#10'implementation'#10'procedure P(A, B: Integer);'#10'begin'#10 +
    '  A := B;'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), TFormatStyle.Default))));
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
  Settings: TFormatStyle;
  Root: Boolean;
begin
  Settings := TFormatStyle.Default;
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
    'insert_final_newline = true'#10, 'C:\P\Unit1.pas', Settings, Root);
  Assert.IsTrue(Root);
  Assert.IsTrue(Settings.UseTabs);
  Assert.AreEqual(4, Settings.IndentSize);
  Assert.AreEqual(#13#10, Settings.EndOfLine);
  Assert.IsFalse(Settings.TrimTrailingWhitespace);
  Assert.IsTrue(Settings.InsertFinalNewline);
end;

procedure TEditorConfigTests.NearerFilesWinUntilRoot;
var
  Files: TDictionary<string, string>;
  Settings: TFormatStyle;
begin
  Files := TDictionary<string, string>.Create;
  try
    Files.Add('c:\.editorconfig', '[*]'#10'indent_size = 8'#10'end_of_line = lf');
    Files.Add('c:\p\.editorconfig', 'root = true'#10'[*]'#10'indent_size = 3');
    Files.Add('c:\p\sub\.editorconfig', '[*.pas]'#10'indent_style = tab');
    Settings := TEditorConfig.ForFile('C:\P\Sub\Unit1.pas',
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := Files.TryGetValue(LowerCase(AFileName), AText);
      end, TFormatStyle.Default);
    Assert.AreEqual(3, Settings.IndentSize);
    Assert.IsTrue(Settings.UseTabs);
    // Oberhalb von root = true wird nichts gelesen.
    Assert.AreEqual('', Settings.EndOfLine);
  finally
    Files.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatterTests);
  TDUnitX.RegisterTestFixture(TEditorConfigTests);

end.
