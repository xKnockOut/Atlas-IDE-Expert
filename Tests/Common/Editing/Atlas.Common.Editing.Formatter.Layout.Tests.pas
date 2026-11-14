unit Atlas.Common.Editing.Formatter.Layout.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract;

type
  /// <summary>Stellung von begin/else, Ausrichtung und Umbruch langer Zeilen (#43).</summary>
  [TestFixture]
  TFormatLayoutTests = class
  private
    function Formatted(const AText: string; const ASettings: TFormatStyle): string;
  public
    [Test]
    procedure PreservesPlacementByDefault;
    [Test]
    procedure MovesBeginToNewLine;
    [Test]
    procedure PullsBeginToSameLine;
    [Test]
    procedure MovesElseToNewLine;
    [Test]
    procedure PullsElseToSameLine;
    /// <summary>#1358: "end", "else" und "begin" auf drei Zeilen werden in einem Lauf eine Zeile (stabil).
    /// </summary>
    [Test]
    procedure PullsElseAndBeginInOnePass;
    [Test]
    procedure AlignsAssignments;
    [Test]
    procedure AlignsDeclarations;
    [Test]
    procedure AlignsComments;
    [Test]
    procedure WrapsLongLines;
    [Test]
    procedure KeepsStringsWhenWrapping;
    [Test]
    procedure RangeTouchesOnlyItsLines;
    [Test]
    procedure EditsCoverJoinedLines;
    [Test]
    procedure IsIdempotentWithAllOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Formatter;

const
  cLF = #10;

{ TFormatLayoutTests }

function TFormatLayoutTests.Formatted(const AText: string; const ASettings: TFormatStyle): string;
begin
  Result := TFormatter.FormatText(AText, TPascalLexer.Tokenize(AText), ASettings);
end;

procedure TFormatLayoutTests.PreservesPlacementByDefault;
const
  cText =
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then begin' + cLF +
    '    B;' + cLF +
    '  end else' + cLF +
    '  begin' + cLF +
    '    C;' + cLF +
    '  end;' + cLF +
    'end;';
begin
  Assert.AreEqual(cText, Formatted(cText, TFormatStyle.Default));
end;

procedure TFormatLayoutTests.MovesBeginToNewLine;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.BeginPlacement := TBlockPlacement.NewLine;
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end;' + cLF +
    '  for I := 0 to 1 do' + cLF +
    '  begin' + cLF +
    '    C;' + cLF +
    '  end;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then begin' + cLF +
    '    B;' + cLF +
    '  end;' + cLF +
    '  for I := 0 to 1 do begin C;' + cLF +
    '  end;' + cLF +
    'end;', mSettings));
end;

procedure TFormatLayoutTests.PullsBeginToSameLine;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.BeginPlacement := TBlockPlacement.SameLine;
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then begin' + cLF +
    '    B;' + cLF +
    '  end;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end;' + cLF +
    'end;', mSettings));
end;

procedure TFormatLayoutTests.MovesElseToNewLine;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.ElsePlacement := TBlockPlacement.NewLine;
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end' + cLF +
    '  else' + cLF +
    '    C;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end else' + cLF +
    '    C;' + cLF +
    'end;', mSettings));
end;

procedure TFormatLayoutTests.PullsElseToSameLine;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.ElsePlacement := TBlockPlacement.SameLine;
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end else' + cLF +
    '    C;' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end' + cLF +
    '  else' + cLF +
    '    C;' + cLF +
    'end;', mSettings));
end;

procedure TFormatLayoutTests.PullsElseAndBeginInOnePass;
var
  mSettings: TFormatStyle;
  mOnce: string;
begin
  mSettings := TFormatStyle.Default;
  mSettings.BeginPlacement := TBlockPlacement.SameLine;
  mSettings.ElsePlacement := TBlockPlacement.SameLine;
  mOnce := Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end' + cLF +
    '  else' + cLF +
    '  begin' + cLF +
    '    C;' + cLF +
    '  end;' + cLF +
    'end;', mSettings);
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then begin' + cLF +
    '    B;' + cLF +
    '  end else begin' + cLF +
    '    C;' + cLF +
    '  end;' + cLF +
    'end;', mOnce);
  Assert.AreEqual(mOnce, Formatted(mOnce, mSettings));
end;

procedure TFormatLayoutTests.AlignsAssignments;
var
  mSettings: TFormatStyle;
  mText: string;
begin
  mText :=
    'procedure P;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  Longer := 2;' + cLF +
    cLF +
    '  B := 3;' + cLF +
    'end;';
  mSettings := TFormatStyle.Default;
  Assert.AreEqual(mText, Formatted(mText, mSettings));
  mSettings.AlignAssignments := True;
  // Eine Leerzeile beendet die Gruppe.
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  A      := 1;' + cLF +
    '  Longer := 2;' + cLF +
    cLF +
    '  B := 3;' + cLF +
    'end;', Formatted(mText, mSettings));
end;

procedure TFormatLayoutTests.AlignsDeclarations;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.AlignDeclarations := True;
  Assert.AreEqual(
    'var' + cLF +
    '  A:      Integer;' + cLF +
    '  Longer: string;' + cLF +
    'const' + cLF +
    '  X     = 1;' + cLF +
    '  YYYYY = 2;',
    Formatted(
    'var' + cLF +
    '  A: Integer;' + cLF +
    '  Longer: string;' + cLF +
    'const' + cLF +
    '  X = 1;' + cLF +
    '  YYYYY = 2;', mSettings));
end;

procedure TFormatLayoutTests.AlignsComments;
var
  mSettings: TFormatStyle;
begin
  mSettings := TFormatStyle.Default;
  mSettings.AlignComments := True;
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  A := 1;       // eins' + cLF +
    '  Longer := 22; // zwei' + cLF +
    'end;',
    Formatted(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  A := 1; // eins' + cLF +
    '  Longer := 22;  // zwei' + cLF +
    'end;', mSettings));
end;

procedure TFormatLayoutTests.WrapsLongLines;
var
  mSettings: TFormatStyle;
  mText: string;
begin
  mText :=
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Call(First, Second, Third);' + cLF +
    'end;';
  mSettings := TFormatStyle.Default;
  Assert.AreEqual(mText, Formatted(mText, mSettings));
  mSettings.MaxLineLength := 22;
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Call(First, Second,' + cLF +
    '    Third);' + cLF +
    'end;', Formatted(mText, mSettings));
  // Vor einem Operator umbrechen, wenn kein Komma passt.
  mSettings.MaxLineLength := 16;
  Assert.AreEqual(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  A := Alpha' + cLF +
    '    + Beta;' + cLF +
    'end;',
    Formatted('procedure P;' + cLF + 'begin' + cLF + '  A := Alpha + Beta;' + cLF + 'end;', mSettings));
end;

procedure TFormatLayoutTests.KeepsStringsWhenWrapping;
var
  mSettings: TFormatStyle;
  mText: string;
begin
  mText :=
    'procedure P;' + cLF +
    'begin' + cLF +
    '  S := ''eins, zwei, drei, vier'';' + cLF +
    'end;';
  mSettings := TFormatStyle.Default;
  mSettings.MaxLineLength := 12;
  Assert.AreEqual(mText, Formatted(mText, mSettings));
end;

procedure TFormatLayoutTests.RangeTouchesOnlyItsLines;
var
  mSettings: TFormatStyle;
  mText: string;
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
begin
  mText :=
    'procedure P;' + cLF +
    'begin' + cLF +
    'A:=1;' + cLF +
    'if A then begin' + cLF +
    'B:=2;' + cLF +
    'end;' + cLF +
    'end;';
  mSettings := TFormatStyle.Default;
  mSettings.BeginPlacement := TBlockPlacement.NewLine;
  mEdits := TFormatter.Edits(mText, TPascalLexer.Tokenize(mText), mSettings, 4, 4);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  for mEdit in mEdits do
  begin
    Assert.AreEqual(4, mEdit.Range.StartPos.Line);
    Assert.AreEqual(4, mEdit.Range.EndPos.Line);
  end;
  Assert.AreEqual('    B := 2;', mEdits[0].NewText);
end;

procedure TFormatLayoutTests.EditsCoverJoinedLines;
var
  mSettings: TFormatStyle;
  mText: string;
  mEdits: TArray<TTextEdit>;
begin
  mText :=
    'procedure P;' + cLF +
    'begin' + cLF +
    '  if A then' + cLF +
    '  begin' + cLF +
    '    B;' + cLF +
    '  end;' + cLF +
    'end;';
  mSettings := TFormatStyle.Default;
  mSettings.BeginPlacement := TBlockPlacement.SameLine;
  mEdits := TFormatter.Edits(mText, TPascalLexer.Tokenize(mText), mSettings);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(2, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual(3, mEdits[0].Range.EndPos.Line);
  Assert.AreEqual('  if A then begin', mEdits[0].NewText);
  // Aufteilen: eine Änderung mit Zeilenumbruch im neuen Text.
  mText := 'procedure P;' + cLF + 'begin' + cLF + '  if A then begin B;' + cLF + '  end;' + cLF + 'end;';
  mSettings.BeginPlacement := TBlockPlacement.NewLine;
  mEdits := TFormatter.Edits(mText, TPascalLexer.Tokenize(mText), mSettings);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual('  if A then' + cLF + '  begin' + cLF + '    B;', mEdits[0].NewText);
end;

procedure TFormatLayoutTests.IsIdempotentWithAllOptions;
const
  cText =
    'procedure P;' + cLF +
    'var' + cLF +
    '  A: Integer; // a' + cLF +
    '  Longer: string; // l' + cLF +
    'begin' + cLF +
    'if A > 0 then begin Call(First, Second, Third, Fourth, Fifth);' + cLF +
    'end else begin' + cLF +
    'A := 1; Longer := ''x'';' + cLF +
    'end;' + cLF +
    'end;';
var
  mSettings: TFormatStyle;
  mOnce: string;
begin
  mSettings := TFormatStyle.Default;
  mSettings.BeginPlacement := TBlockPlacement.NewLine;
  mSettings.ElsePlacement := TBlockPlacement.NewLine;
  mSettings.MaxLineLength := 30;
  mSettings.AlignAssignments := True;
  mSettings.AlignDeclarations := True;
  mSettings.AlignComments := True;
  mOnce := Formatted(cText, mSettings);
  Assert.AreEqual(mOnce, Formatted(mOnce, mSettings));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatLayoutTests);

end.
