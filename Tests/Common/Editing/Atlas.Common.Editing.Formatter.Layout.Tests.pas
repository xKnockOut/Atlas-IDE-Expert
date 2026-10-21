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
  LF = #10;

{ TFormatLayoutTests }

function TFormatLayoutTests.Formatted(const AText: string; const ASettings: TFormatStyle): string;
begin
  Result := TFormatter.FormatText(AText, TPascalLexer.Tokenize(AText), ASettings);
end;

procedure TFormatLayoutTests.PreservesPlacementByDefault;
const
  Text =
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then begin' + LF +
    '    B;' + LF +
    '  end else' + LF +
    '  begin' + LF +
    '    C;' + LF +
    '  end;' + LF +
    'end;';
begin
  Assert.AreEqual(Text, Formatted(Text, TFormatStyle.Default));
end;

procedure TFormatLayoutTests.MovesBeginToNewLine;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.BeginPlacement := TBlockPlacement.NewLine;
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '  end;' + LF +
    '  for I := 0 to 1 do' + LF +
    '  begin' + LF +
    '    C;' + LF +
    '  end;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then begin' + LF +
    '    B;' + LF +
    '  end;' + LF +
    '  for I := 0 to 1 do begin C;' + LF +
    '  end;' + LF +
    'end;', Settings));
end;

procedure TFormatLayoutTests.PullsBeginToSameLine;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.BeginPlacement := TBlockPlacement.SameLine;
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then begin' + LF +
    '    B;' + LF +
    '  end;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '  end;' + LF +
    'end;', Settings));
end;

procedure TFormatLayoutTests.MovesElseToNewLine;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.ElsePlacement := TBlockPlacement.NewLine;
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '  end' + LF +
    '  else' + LF +
    '    C;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '  end else' + LF +
    '    C;' + LF +
    'end;', Settings));
end;

procedure TFormatLayoutTests.PullsElseToSameLine;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.ElsePlacement := TBlockPlacement.SameLine;
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '  end else' + LF +
    '    C;' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '  end' + LF +
    '  else' + LF +
    '    C;' + LF +
    'end;', Settings));
end;

procedure TFormatLayoutTests.AlignsAssignments;
var
  Settings: TFormatStyle;
  Text: string;
begin
  Text :=
    'procedure P;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  Longer := 2;' + LF +
    LF +
    '  B := 3;' + LF +
    'end;';
  Settings := TFormatStyle.Default;
  Assert.AreEqual(Text, Formatted(Text, Settings));
  Settings.AlignAssignments := True;
  // Eine Leerzeile beendet die Gruppe.
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  A      := 1;' + LF +
    '  Longer := 2;' + LF +
    LF +
    '  B := 3;' + LF +
    'end;', Formatted(Text, Settings));
end;

procedure TFormatLayoutTests.AlignsDeclarations;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.AlignDeclarations := True;
  Assert.AreEqual(
    'var' + LF +
    '  A:      Integer;' + LF +
    '  Longer: string;' + LF +
    'const' + LF +
    '  X     = 1;' + LF +
    '  YYYYY = 2;',
    Formatted(
    'var' + LF +
    '  A: Integer;' + LF +
    '  Longer: string;' + LF +
    'const' + LF +
    '  X = 1;' + LF +
    '  YYYYY = 2;', Settings));
end;

procedure TFormatLayoutTests.AlignsComments;
var
  Settings: TFormatStyle;
begin
  Settings := TFormatStyle.Default;
  Settings.AlignComments := True;
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  A := 1;       // eins' + LF +
    '  Longer := 22; // zwei' + LF +
    'end;',
    Formatted(
    'procedure P;' + LF +
    'begin' + LF +
    '  A := 1; // eins' + LF +
    '  Longer := 22;  // zwei' + LF +
    'end;', Settings));
end;

procedure TFormatLayoutTests.WrapsLongLines;
var
  Settings: TFormatStyle;
  Text: string;
begin
  Text :=
    'procedure P;' + LF +
    'begin' + LF +
    '  Call(First, Second, Third);' + LF +
    'end;';
  Settings := TFormatStyle.Default;
  Assert.AreEqual(Text, Formatted(Text, Settings));
  Settings.MaxLineLength := 22;
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  Call(First, Second,' + LF +
    '    Third);' + LF +
    'end;', Formatted(Text, Settings));
  // Vor einem Operator umbrechen, wenn kein Komma passt.
  Settings.MaxLineLength := 16;
  Assert.AreEqual(
    'procedure P;' + LF +
    'begin' + LF +
    '  A := Alpha' + LF +
    '    + Beta;' + LF +
    'end;',
    Formatted('procedure P;' + LF + 'begin' + LF + '  A := Alpha + Beta;' + LF + 'end;', Settings));
end;

procedure TFormatLayoutTests.KeepsStringsWhenWrapping;
var
  Settings: TFormatStyle;
  Text: string;
begin
  Text :=
    'procedure P;' + LF +
    'begin' + LF +
    '  S := ''eins, zwei, drei, vier'';' + LF +
    'end;';
  Settings := TFormatStyle.Default;
  Settings.MaxLineLength := 12;
  Assert.AreEqual(Text, Formatted(Text, Settings));
end;

procedure TFormatLayoutTests.RangeTouchesOnlyItsLines;
var
  Settings: TFormatStyle;
  Text: string;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
begin
  Text :=
    'procedure P;' + LF +
    'begin' + LF +
    'A:=1;' + LF +
    'if A then begin' + LF +
    'B:=2;' + LF +
    'end;' + LF +
    'end;';
  Settings := TFormatStyle.Default;
  Settings.BeginPlacement := TBlockPlacement.NewLine;
  Edits := TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), Settings, 4, 4);
  Assert.AreEqual(1, Integer(Length(Edits)));
  for Edit in Edits do
  begin
    Assert.AreEqual(4, Edit.Range.StartPos.Line);
    Assert.AreEqual(4, Edit.Range.EndPos.Line);
  end;
  Assert.AreEqual('    B := 2;', Edits[0].NewText);
end;

procedure TFormatLayoutTests.EditsCoverJoinedLines;
var
  Settings: TFormatStyle;
  Text: string;
  Edits: TArray<TTextEdit>;
begin
  Text :=
    'procedure P;' + LF +
    'begin' + LF +
    '  if A then' + LF +
    '  begin' + LF +
    '    B;' + LF +
    '  end;' + LF +
    'end;';
  Settings := TFormatStyle.Default;
  Settings.BeginPlacement := TBlockPlacement.SameLine;
  Edits := TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), Settings);
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(2, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(3, Edits[0].Range.EndPos.Line);
  Assert.AreEqual('  if A then begin', Edits[0].NewText);
  // Aufteilen: eine Änderung mit Zeilenumbruch im neuen Text.
  Text := 'procedure P;' + LF + 'begin' + LF + '  if A then begin B;' + LF + '  end;' + LF + 'end;';
  Settings.BeginPlacement := TBlockPlacement.NewLine;
  Edits := TFormatter.Edits(Text, TPascalLexer.Tokenize(Text), Settings);
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual('  if A then' + LF + '  begin' + LF + '    B;', Edits[0].NewText);
end;

procedure TFormatLayoutTests.IsIdempotentWithAllOptions;
const
  Text =
    'procedure P;' + LF +
    'var' + LF +
    '  A: Integer; // a' + LF +
    '  Longer: string; // l' + LF +
    'begin' + LF +
    'if A > 0 then begin Call(First, Second, Third, Fourth, Fifth);' + LF +
    'end else begin' + LF +
    'A := 1; Longer := ''x'';' + LF +
    'end;' + LF +
    'end;';
var
  Settings: TFormatStyle;
  Once: string;
begin
  Settings := TFormatStyle.Default;
  Settings.BeginPlacement := TBlockPlacement.NewLine;
  Settings.ElsePlacement := TBlockPlacement.NewLine;
  Settings.MaxLineLength := 30;
  Settings.AlignAssignments := True;
  Settings.AlignDeclarations := True;
  Settings.AlignComments := True;
  Once := Formatted(Text, Settings);
  Assert.AreEqual(Once, Formatted(Once, Settings));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatLayoutTests);

end.
