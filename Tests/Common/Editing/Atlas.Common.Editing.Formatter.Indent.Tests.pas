unit Atlas.Common.Editing.Formatter.Indent.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract;

type
  /// <summary>Einrückung nach der Blockstruktur (#43).</summary>
  [TestFixture]
  TBlockIndenterTests = class
  private
    function Formatted(const AText: string): string; overload;
    function Formatted(const AText: string; const ASettings: TFormatStyle): string; overload;
  public
    [Test]
    procedure IndentsRoutineBlocks;
    [Test]
    procedure IndentsSingleStatements;
    [Test]
    procedure IndentsTryCaseAndRepeat;
    [Test]
    procedure IndentsSectionsAndClassBody;
    [Test]
    procedure KeepsContinuationOffset;
    [Test]
    procedure CommentFollowsNextLine;
    [Test]
    procedure KeepsDirectivesAsmAndElseBranch;
    [Test]
    procedure IndentsAnonymousMethods;
    [Test]
    procedure KeepsLinesInMultilineTokens;
    [Test]
    procedure UsesTabsAndIndentSize;
    [Test]
    procedure IsIdempotent;
    [Test]
    procedure KeepsTokens;
    [Test]
    procedure IsSwitchable;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Editing.Formatter.Indent;

const
  LF = #10;

{ TBlockIndenterTests }

function TBlockIndenterTests.Formatted(const AText: string): string;
begin
  Result := Formatted(AText, TFormatStyle.Default);
end;

function TBlockIndenterTests.Formatted(const AText: string; const ASettings: TFormatStyle): string;
begin
  Result := TFormatter.FormatText(AText, TPascalLexer.Tokenize(AText), ASettings);
end;

procedure TBlockIndenterTests.IndentsRoutineBlocks;
begin
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '    while C do' + LF +
    '    begin' + LF +
    '      D;' + LF +
    '    end;' + LF +
    '  end;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    '    begin' + LF +
    'if A then' + LF +
    'begin' + LF +
    '        B;' + LF +
    ' while C do' + LF +
    ' begin' + LF +
    'D;' + LF +
    '      end;' + LF +
    'end;' + LF +
    '  end;'));
end;

procedure TBlockIndenterTests.IndentsSingleStatements;
begin
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '    B' + LF +
    '  else if C then' + LF +
    '    D' + LF +
    '  else' + LF +
    '    E;' + LF +
    '  for I := 0 to 9 do' + LF +
    '    F(I);' + LF +
    '  G;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    'if A then' + LF +
    'B' + LF +
    'else if C then' + LF +
    'D' + LF +
    'else' + LF +
    'E;' + LF +
    'for I := 0 to 9 do' + LF +
    'F(I);' + LF +
    'G;' + LF +
    'end;'));
end;

procedure TBlockIndenterTests.IndentsTryCaseAndRepeat;
begin
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  try' + LF +
    '    case A of' + LF +
    '      1:' + LF +
    '        B;' + LF +
    '      2, 3: C;' + LF +
    '    else' + LF +
    '      D;' + LF +
    '    end;' + LF +
    '  finally' + LF +
    '    repeat' + LF +
    '      E;' + LF +
    '    until F;' + LF +
    '  end;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    'try' + LF +
    'case A of' + LF +
    '1:' + LF +
    'B;' + LF +
    '2, 3: C;' + LF +
    'else' + LF +
    'D;' + LF +
    'end;' + LF +
    'finally' + LF +
    'repeat' + LF +
    'E;' + LF +
    'until F;' + LF +
    'end;' + LF +
    'end;'));
end;

procedure TBlockIndenterTests.IndentsSectionsAndClassBody;
begin
  Assert.AreEqual(
    'unit U;' + LF +
    LF +
    'interface' + LF +
    LF +
    'uses' + LF +
    '  A, B;' + LF +
    LF +
    'type' + LF +
    '  TX = class' + LF +
    '  private' + LF +
    '    FA: Integer;' + LF +
    '  public' + LF +
    '    procedure P;' + LF +
    '  end;' + LF +
    LF +
    'const' + LF +
    '  C = 1;' + LF +
    LF +
    'implementation' + LF +
    LF +
    'procedure TX.P;' + LF +
    'var' + LF +
    '  I: Integer;' + LF +
    'begin' + LF +
    '  I := C;' + LF +
    'end;' + LF +
    LF +
    'end.',
    Formatted(
    'unit U;' + LF +
    LF +
    'interface' + LF +
    LF +
    'uses' + LF +
    'A, B;' + LF +
    LF +
    'type' + LF +
    'TX = class' + LF +
    '    private' + LF +
    'FA: Integer;' + LF +
    'public' + LF +
    'procedure P;' + LF +
    'end;' + LF +
    LF +
    'const' + LF +
    '    C = 1;' + LF +
    LF +
    'implementation' + LF +
    LF +
    'procedure TX.P;' + LF +
    'var' + LF +
    'I: Integer;' + LF +
    'begin' + LF +
    'I := C;' + LF +
    'end;' + LF +
    LF +
    'end.'));
end;

procedure TBlockIndenterTests.KeepsContinuationOffset;
begin
  // Folgezeilen behalten ihren Abstand zur ersten Zeile der Anweisung.
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  A := F(1,' + LF +
    '      2);' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '      A := F(1,' + LF +
    '          2);' + LF +
    'end;'));
end;

procedure TBlockIndenterTests.CommentFollowsNextLine;
begin
  // Kommentarzeilen behalten ihren Abstand zur folgenden Codezeile.
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  // Hinweis' + LF +
    '    // tiefer' + LF +
    '  A;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '      // Hinweis' + LF +
    '        // tiefer' + LF +
    '      A;' + LF +
    'end;'));
end;

procedure TBlockIndenterTests.KeepsDirectivesAsmAndElseBranch;
const
  Text =
    'procedure P;' + LF +
    'begin' + LF +
    '{$IFDEF X}' + LF +
    '  A;' + LF +
    '{$ELSE}' + LF +
    '      B;' + LF +
    '{$ENDIF}' + LF +
    'end;' + LF +
    'procedure Q;' + LF +
    'asm' + LF +
    '        MOV EAX, 1' + LF +
    'end;';
begin
  Assert.AreEqual(Text, Formatted(Text));
end;

procedure TBlockIndenterTests.IndentsAnonymousMethods;
begin
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  Run(' + LF +
    '    procedure' + LF +
    '    begin' + LF +
    '      A;' + LF +
    '    end);' + LF +
    '  B;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '  Run(' + LF +
    '    procedure' + LF +
    '    begin' + LF +
    '  A;' + LF +
    '    end);' + LF +
    '      B;' + LF +
    'end;'));
end;

procedure TBlockIndenterTests.KeepsLinesInMultilineTokens;
var
  Text: string;
  Tokens: TArray<TPascalToken>;
  Columns: TArray<Integer>;
begin
  Text := 'procedure P;' + LF + 'begin' + LF + '{ eins' + LF + '      zwei }' + LF + 'A;' + LF + 'end;';
  Tokens := TPascalLexer.Tokenize(Text);
  Columns := TBlockIndenter.Columns(Tokens, [0, 0, 0, 6, 0, 0], 2);
  Assert.AreEqual(TBlockIndenter.Keep, Columns[3]);
  Assert.AreEqual(2, Columns[4]);
  Assert.AreEqual(0, Columns[5]);
end;

procedure TBlockIndenterTests.UsesTabsAndIndentSize;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.IndentSize := 4;
  Assert.AreEqual('procedure P;' + LF + 'begin' + LF + '    A;' + LF + 'end;',
    Formatted('procedure P;' + LF + 'begin' + LF + 'A;' + LF + 'end;', Settings));
  Settings.UseTabs := True;
  Assert.AreEqual('procedure P;' + LF + 'begin' + LF + #9'A;' + LF + 'end;',
    Formatted('procedure P;' + LF + 'begin' + LF + 'A;' + LF + 'end;', Settings));
end;

procedure TBlockIndenterTests.IsIdempotent;
const
  Text =
    'unit U;' + LF +
    'interface' + LF +
    'type' + LF +
    'TX = class' + LF +
    'procedure P(A,' + LF +
    'B: Integer); virtual;' + LF +
    'end;' + LF +
    'implementation' + LF +
    'procedure TX.P(A, B: Integer);' + LF +
    'begin' + LF +
    'if A > B then begin' + LF +
    'case A of 1: B := 2; end;' + LF +
    'end else' + LF +
    'try A := B; except on E: Exception do raise; end;' + LF +
    'end;' + LF +
    'end.';
var
  Once: string;
begin
  Once := Formatted(Text);
  Assert.AreEqual(Once, Formatted(Once));
end;

procedure TBlockIndenterTests.KeepsTokens;
const
  Text =
    'procedure P;' + LF +
    'begin' + LF +
    'if A then begin { c } B := ''x  y'';' + LF +
    'end else C;' + LF +
    'end;';
var
  Before, After: TArray<TPascalToken>;
  Index: Integer;
begin
  Before := TPascalLexer.Tokenize(Text);
  After := TPascalLexer.Tokenize(Formatted(Text));
  Assert.AreEqual(Integer(Length(Before)), Integer(Length(After)));
  for Index := 0 to High(Before) do
    Assert.AreEqual(Before[Index].Text, After[Index].Text);
end;

procedure TBlockIndenterTests.IsSwitchable;
var
  Settings: TFormatStyle;
  Text: string;
begin
  Settings := TFormatStyle.Default;
  Settings.Reindent := False;
  Text := 'procedure P;' + LF + 'begin' + LF + '      A;' + LF + 'end;';
  Assert.AreEqual(Text, Formatted(Text, Settings));
end;

initialization
  TDUnitX.RegisterTestFixture(TBlockIndenterTests);

end.
