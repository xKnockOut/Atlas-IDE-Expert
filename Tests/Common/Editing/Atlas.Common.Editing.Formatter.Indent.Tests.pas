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
    [Test]
    procedure ReportsLineInfo;
    [Test]
    procedure MeasuresAndBuildsIndent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.Formatter,
  Atlas.Common.Editing.Formatter.Indent;

const
  cLF = #10;

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
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '    while C do' + cLF +
    '    begin' + cLF +
    '      D;' + cLF +
    '    end;' + cLF +
    '  end;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    '    begin' + cLF +
    'if A then' + cLF +
    'begin' + cLF +
    '        B;' + cLF +
    ' while C do' + cLF +
    ' begin' + cLF +
    'D;' + cLF +
    '      end;' + cLF +
    'end;' + cLF +
    '  end;'));
end;

procedure TBlockIndenterTests.IndentsSingleStatements;
begin
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '    B' + cLF +
    '  else if C then' + cLF +
    '    D' + cLF +
    '  else' + cLF +
    '    E;' + cLF +
    '  for I := 0 to 9 do' + cLF +
    '    F(I);' + cLF +
    '  G;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    'if A then' + cLF +
    'B' + cLF +
    'else if C then' + cLF +
    'D' + cLF +
    'else' + cLF +
    'E;' + cLF +
    'for I := 0 to 9 do' + cLF +
    'F(I);' + cLF +
    'G;' + cLF +
    'end;'));
end;

procedure TBlockIndenterTests.IndentsTryCaseAndRepeat;
begin
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  try' + cLF +
    '    case A of' + cLF +
    '      1:' + cLF +
    '        B;' + cLF +
    '      2, 3: C;' + cLF +
    '    else' + cLF +
    '      D;' + cLF +
    '    end;' + cLF +
    '  finally' + cLF +
    '    repeat' + cLF +
    '      E;' + cLF +
    '    until F;' + cLF +
    '  end;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    'try' + cLF +
    'case A of' + cLF +
    '1:' + cLF +
    'B;' + cLF +
    '2, 3: C;' + cLF +
    'else' + cLF +
    'D;' + cLF +
    'end;' + cLF +
    'finally' + cLF +
    'repeat' + cLF +
    'E;' + cLF +
    'until F;' + cLF +
    'end;' + cLF +
    'end;'));
end;

const
  /// <summary>Eingabe ohne Einrückung der Abschnitte und des Klassenrumpfs.</summary>
  cSectionsUnindented =
    'unit U;' + cLF +
    cLF +
    'interface' + cLF +
    cLF +
    'uses' + cLF +
    'A, B;' + cLF +
    cLF +
    'type' + cLF +
    'TX = class' + cLF +
    '    private' + cLF +
    'FA: Integer;' + cLF +
    'public' + cLF +
    'procedure P;' + cLF +
    'end;' + cLF +
    cLF +
    'const' + cLF +
    '    C = 1;' + cLF +
    cLF +
    'implementation' + cLF +
    cLF +
    'procedure TX.P;' + cLF +
    'var' + cLF +
    'I: Integer;' + cLF +
    'begin' + cLF +
    'I := C;' + cLF +
    'end;' + cLF +
    cLF +
    'end.';

procedure TBlockIndenterTests.IndentsSectionsAndClassBody;
begin
  Assert.AreEqual(
    'unit U;' + cLF +
    cLF +
    'interface' + cLF +
    cLF +
    'uses' + cLF +
    '  A, B;' + cLF +
    cLF +
    'type' + cLF +
    '  TX = class' + cLF +
    '  private' + cLF +
    '    FA: Integer;' + cLF +
    '  public' + cLF +
    '    procedure P;' + cLF +
    '  end;' + cLF +
    cLF +
    'const' + cLF +
    '  C = 1;' + cLF +
    cLF +
    'implementation' + cLF +
    cLF +
    'procedure TX.P;' + cLF +
    'var' + cLF +
    '  I: Integer;' + cLF +
    'begin' + cLF +
    '  I := C;' + cLF +
    'end;' + cLF +
    cLF +
    'end.',
    Formatted(cSectionsUnindented));
end;

procedure TBlockIndenterTests.KeepsContinuationOffset;
begin
  // Folgezeilen behalten ihren Abstand zur ersten Zeile der Anweisung.
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  A := F(1,' + cLF +
    '      2);' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '      A := F(1,' + cLF +
    '          2);' + cLF +
    'end;'));
end;

procedure TBlockIndenterTests.CommentFollowsNextLine;
begin
  // Kommentarzeilen behalten ihren Abstand zur folgenden Codezeile.
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  // Hinweis' + cLF +
    '    // tiefer' + cLF +
    '  A;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '      // Hinweis' + cLF +
    '        // tiefer' + cLF +
    '      A;' + cLF +
    'end;'));
end;

procedure TBlockIndenterTests.KeepsDirectivesAsmAndElseBranch;
const
  cText =
    'procedure P;' + cLF +
    'begin' + cLF +
    '{$IFDEF X}' + cLF +
    '  A;' + cLF +
    '{$ELSE}' + cLF +
    '      B;' + cLF +
    '{$ENDIF}' + cLF +
    'end;' + cLF +
    'procedure Q;' + cLF +
    'asm' + cLF +
    '        MOV EAX, 1' + cLF +
    'end;';
begin
  Assert.AreEqual(cText, Formatted(cText));
end;

procedure TBlockIndenterTests.IndentsAnonymousMethods;
begin
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Run(' + cLF +
    '    procedure' + cLF +
    '    begin' + cLF +
    '      A;' + cLF +
    '    end);' + cLF +
    '  B;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Run(' + cLF +
    '    procedure' + cLF +
    '    begin' + cLF +
    '  A;' + cLF +
    '    end);' + cLF +
    '      B;' + cLF +
    'end;'));
end;

procedure TBlockIndenterTests.KeepsLinesInMultilineTokens;
var
  mText: string;
  mTokens: TArray<TPascalToken>;
  mColumns: TArray<Integer>;
begin
  mText := 'procedure P;' + cLF + 'begin' + cLF + '{ eins' + cLF + '      zwei }' + cLF + 'A;' + cLF + 'end;';
  mTokens := TPascalLexer.Tokenize(mText);
  mColumns := TBlockIndenter.Columns(mTokens, [0, 0, 0, 6, 0, 0], 2);
  Assert.AreEqual(TBlockIndenter.cKeep, mColumns[3]);
  Assert.AreEqual(2, mColumns[4]);
  Assert.AreEqual(0, mColumns[5]);
end;

procedure TBlockIndenterTests.UsesTabsAndIndentSize;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.IndentSize := 4;
  Assert.AreEqual('procedure P;' + cLF + 'begin' + cLF + '    A;' + cLF + 'end;',
    Formatted('procedure P;' + cLF + 'begin' + cLF + 'A;' + cLF + 'end;', mSettings));
  mSettings.UseTabs := True;
  Assert.AreEqual('procedure P;' + cLF + 'begin' + cLF + #9'A;' + cLF + 'end;',
    Formatted('procedure P;' + cLF + 'begin' + cLF + 'A;' + cLF + 'end;', mSettings));
end;

procedure TBlockIndenterTests.IsIdempotent;
const
  cText =
    'unit U;' + cLF +
    'interface' + cLF +
    'type' + cLF +
    'TX = class' + cLF +
    'procedure P(A,' + cLF +
    'B: Integer); virtual;' + cLF +
    'end;' + cLF +
    'implementation' + cLF +
    'procedure TX.P(A, B: Integer);' + cLF +
    'begin' + cLF +
    'if A > B then begin' + cLF +
    'case A of 1: B := 2; end;' + cLF +
    'end else' + cLF +
    'try A := B; except on E: Exception do raise; end;' + cLF +
    'end;' + cLF +
    'end.';
var
  mOnce: string;
begin
  mOnce := Formatted(cText);
  Assert.AreEqual(mOnce, Formatted(mOnce));
end;

procedure TBlockIndenterTests.KeepsTokens;
const
  cText =
    'procedure P;' + cLF +
    'begin' + cLF +
    'if A then begin { c } B := ''x  y'';' + cLF +
    'end else C;' + cLF +
    'end;';
var
  mBefore, mAfter: TArray<TPascalToken>;
  mIndex: Integer;
begin
  mBefore := TPascalLexer.Tokenize(cText);
  mAfter := TPascalLexer.Tokenize(Formatted(cText));
  Assert.AreEqual(Integer(Length(mBefore)), Integer(Length(mAfter)));
  for mIndex := 0 to High(mBefore) do
  begin
    Assert.AreEqual(mBefore[mIndex].Text, mAfter[mIndex].Text);
  end;
end;

procedure TBlockIndenterTests.ReportsLineInfo;
var
  mInfo: TArray<TIndentLineInfo>;
begin
  // Zeilen: 0 begin, 1 X := A +, 2 B;, 3 Y := 1;, 4 end;
  mInfo := TBlockIndenter.Lines(TPascalLexer.Tokenize('begin' + cLF + 'X := A +' + cLF + 'B;' + cLF + 'Y := 1;' + cLF +
    'end;'), [0, 0, 0, 0, 0], 2);
  Assert.AreEqual(5, Integer(Length(mInfo)));
  Assert.IsTrue(mInfo[1].Placed);
  Assert.AreEqual(2, mInfo[1].Column);
  Assert.IsFalse(mInfo[1].Continued);
  Assert.IsTrue(mInfo[2].Continued, 'Fortsetzung');
  Assert.AreEqual(1, mInfo[2].StatementLine);
  Assert.IsFalse(mInfo[3].Continued);
  Assert.AreEqual(2, mInfo[3].Column);
  Assert.AreEqual(0, mInfo[4].Column);
end;

procedure TBlockIndenterTests.MeasuresAndBuildsIndent;
var
  mLength: Integer;
begin
  Assert.AreEqual(6, TBlockIndenter.LeadingColumns(#9'  X', 4, mLength));
  Assert.AreEqual(3, mLength);
  Assert.AreEqual(0, TBlockIndenter.LeadingColumns('X', 2, mLength));
  Assert.AreEqual(0, mLength);
  Assert.AreEqual('      ', TBlockIndenter.IndentText(6, 4, False));
  Assert.AreEqual(#9'  ', TBlockIndenter.IndentText(6, 4, True));
  Assert.AreEqual('', TBlockIndenter.IndentText(-2, 2, True));
end;

procedure TBlockIndenterTests.IsSwitchable;
var
  mSettings: TFormatStyle;
  mText: string;
begin
  mSettings := TFormatStyle.Default;
  mSettings.Reindent := False;
  mText := 'procedure P;' + cLF + 'begin' + cLF + '      A;' + cLF + 'end;';
  Assert.AreEqual(mText, Formatted(mText, mSettings));
end;

initialization
  TDUnitX.RegisterTestFixture(TBlockIndenterTests);

end.
