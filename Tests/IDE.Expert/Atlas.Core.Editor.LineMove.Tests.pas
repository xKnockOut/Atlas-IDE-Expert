unit Atlas.Core.Editor.LineMove.Tests;

// Tests für Zeilen und Blöcke verschieben und duplizieren (#634): Einzug über
// Blockgrenzen, Duplikate mit Cursor, Methoden samt Kommentaren und die
// Ersetzung ganzer Zeilen für den Puffer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLineMoveTests = class
  public
    [Test]
    procedure SwapsWithNeighbour;
    [Test]
    procedure IndentFollowsBlockDepth;
    [Test]
    procedure MovingUpLeavesBlock;
    [Test]
    procedure FinallyAndElseKeepIndent;
    [Test]
    procedure MovesSelectionAndKeepsEmptyLines;
    [Test]
    procedure TabIndentedLinesGetTabs;
    [Test]
    procedure StopsAtStartAndEnd;
    [Test]
    procedure DuplicatesAboveAndBelow;
    [Test]
    procedure MapsCursorWithIndent;
    [Test]
    procedure MovesMethodWithCommentsDown;
    [Test]
    procedure MovesMethodUp;
    [Test]
    procedure MethodNeedsNeighbourWithoutCodeBetween;
    [Test]
    procedure CursorInBodyMovesLineOnly;
    [Test]
    procedure DifferenceReplacesWholeLines;
    [Test]
    procedure CommentOnlyTextWithoutDirectives;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.LineMove;

const
  Loop =
    'procedure P;'#10 +
    'begin'#10 +
    '  A;'#10 +
    '  while X do'#10 +
    '  begin'#10 +
    '    B;'#10 +
    '  end;'#10 +
    'end;';

  Methods =
    'implementation'#10 +
    #10 +
    '{ TFoo }'#10 +
    #10 +
    '/// Erste'#10 +
    'procedure TFoo.A;'#10 +
    'begin'#10 +
    '  X;'#10 +
    'end;'#10 +
    #10 +
    '// Zweite'#10 +
    '{ über zwei'#10 +
    '  Zeilen }'#10 +
    'procedure TFoo.B(AValue: Integer);'#10 +
    'begin'#10 +
    '  Y;'#10 +
    'end;'#10 +
    #10 +
    'end.';

function Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join(#10, ALines);
end;

/// <summary>Text nach dem Verschieben bzw. Duplizieren; '-', wenn nichts geht.</summary>
function Moved(const AText: string; AFirst, ALast, AMethodLine: Integer; AKind: TAtlasLineMoveKind): string;
var
  Move: TAtlasLineMove;
begin
  Result := '-';
  if TAtlasLineMover.Compute(AText, AFirst, ALast, AMethodLine, AKind, 2, Move) then
    Result := Joined(TAtlasLineMover.Apply(AText.Split([#10]), Move));
end;

{ TAtlasLineMoveTests }

procedure TAtlasLineMoveTests.SwapsWithNeighbour;
begin
  Assert.AreEqual('b'#10'a'#10'c', Moved('a'#10'b'#10'c', 0, 0, 0, TAtlasLineMoveKind.MoveDown));
  Assert.AreEqual('a'#10'c'#10'b', Moved('a'#10'b'#10'c', 2, 2, 2, TAtlasLineMoveKind.MoveUp));
end;

procedure TAtlasLineMoveTests.IndentFollowsBlockDepth;
var
  Text: string;
begin
  // "A;" wandert abwärts: über "while" ohne Änderung, über "begin" eine Ebene tiefer, über "end;" zurück.
  Text := Moved(Loop, 2, 2, 2, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual('  A;', Text.Split([#10])[3]);
  Text := Moved(Text, 3, 3, 3, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual('    A;', Text.Split([#10])[4]);
  Text := Moved(Text, 4, 4, 4, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual('    A;', Text.Split([#10])[5]);
  Text := Moved(Text, 5, 5, 5, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual(
    'procedure P;'#10 +
    'begin'#10 +
    '  while X do'#10 +
    '  begin'#10 +
    '    B;'#10 +
    '  end;'#10 +
    '  A;'#10 +
    'end;', Text);
end;

procedure TAtlasLineMoveTests.MovingUpLeavesBlock;
var
  Text: string;
begin
  // "B;" aufwärts über "begin" eine Ebene höher; wieder abwärts eine tiefer.
  Text := Moved(Loop, 5, 5, 5, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('  B;', Text.Split([#10])[4]);
  Assert.AreEqual(Loop, Moved(Text, 4, 4, 4, TAtlasLineMoveKind.MoveDown));
  // Ohne Blockgrenze bleibt der Einzug, auch für "end;" selbst.
  Text := Moved(Loop, 6, 6, 6, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('  end;', Text.Split([#10])[5]);
  // Aufwärts über "end;" in den Block hinein.
  Text := Moved(Loop + #10'C;', 8, 8, 8, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('  C;', Text.Split([#10])[7], 'über "end;" der Routine');
  Text := Moved(Text, 7, 7, 7, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('    C;', Text.Split([#10])[6], 'über "end;" der Schleife');
end;

procedure TAtlasLineMoveTests.FinallyAndElseKeepIndent;
const
  TryText =
    'begin'#10 +
    '  try'#10 +
    '    A;'#10 +
    '  finally'#10 +
    '    B;'#10 +
    '  end;'#10 +
    '  if X then'#10 +
    '  begin'#10 +
    '    C;'#10 +
    '  end else begin'#10 +
    '    D;'#10 +
    '  end;'#10 +
    'end;';
begin
  Assert.AreEqual('    A;', Moved(TryText, 2, 2, 2, TAtlasLineMoveKind.MoveDown).Split([#10])[3]);
  Assert.AreEqual('    D;', Moved(TryText, 10, 10, 10, TAtlasLineMoveKind.MoveUp).Split([#10])[9]);
  Assert.AreEqual('    C;', Moved(TryText, 8, 8, 8, TAtlasLineMoveKind.MoveDown).Split([#10])[9]);
end;

procedure TAtlasLineMoveTests.MovesSelectionAndKeepsEmptyLines;
const
  Text =
    'begin'#10 +
    '  A;'#10 +
    ''#10 +
    '  B;'#10 +
    '  with X do'#10 +
    '  begin'#10 +
    '  end;'#10 +
    'end;';
var
  Move: TAtlasLineMove;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(Moved(Text, 1, 3, -1, TAtlasLineMoveKind.MoveDown), 2, 4, -1,
    TAtlasLineMoveKind.MoveDown, 2, Move));
  Assert.AreEqual(
    'begin'#10 +
    '  with X do'#10 +
    '  begin'#10 +
    '    A;'#10 +
    ''#10 +
    '    B;'#10 +
    '  end;'#10 +
    'end;', Joined(TAtlasLineMover.Apply(Moved(Text, 1, 3, -1, TAtlasLineMoveKind.MoveDown).Split([#10]), Move)));
  Assert.AreEqual(3, Move.FirstLine);
  Assert.AreEqual(5, Move.LastLine);
  Assert.AreEqual(2, Move.IndentShift[0]);
  Assert.AreEqual(0, Move.IndentShift[1], 'leere Zeile bleibt leer');
end;

procedure TAtlasLineMoveTests.TabIndentedLinesGetTabs;
begin
  Assert.AreEqual(#9#9'A;', Moved('begin'#10#9'A;'#10#9'begin'#10#9'end;'#10'end;', 1, 1, 1,
    TAtlasLineMoveKind.MoveDown).Split([#10])[2]);
  Assert.AreEqual('A;', TAtlasLineMover.Reindent(#9'A;', -1, 4));
  Assert.AreEqual(' A;', TAtlasLineMover.Reindent('   A;', -1, 2));
  Assert.AreEqual('A;', TAtlasLineMover.Reindent(' A;', -2, 2), 'nicht weiter als bis zum Rand');
  Assert.AreEqual('   ', TAtlasLineMover.Reindent('   ', 1, 2));
end;

procedure TAtlasLineMoveTests.StopsAtStartAndEnd;
begin
  Assert.AreEqual('-', Moved('a'#10'b', 0, 0, 0, TAtlasLineMoveKind.MoveUp));
  Assert.AreEqual('-', Moved('a'#10'b', 0, 1, -1, TAtlasLineMoveKind.MoveDown));
  Assert.AreEqual('-', Moved('a'#10'b', 1, 2, -1, TAtlasLineMoveKind.MoveDown), 'Zeile außerhalb');
end;

procedure TAtlasLineMoveTests.DuplicatesAboveAndBelow;
var
  Move: TAtlasLineMove;
  Line, Character: Integer;
begin
  Assert.AreEqual('a'#10'b'#10'c'#10'b'#10'c', Moved('a'#10'b'#10'c', 1, 2, -1, TAtlasLineMoveKind.DuplicateDown));
  Assert.AreEqual('a'#10'b'#10'b'#10'c', Moved('a'#10'b'#10'c', 1, 1, 1, TAtlasLineMoveKind.DuplicateUp));
  // Auch an der letzten Zeile; Methodenköpfe werden nur als Zeilen dupliziert.
  Assert.AreEqual('a'#10'b'#10'b', Moved('a'#10'b', 1, 1, 1, TAtlasLineMoveKind.DuplicateDown));
  // Der Cursor wandert mit der Kopie.
  Assert.IsTrue(TAtlasLineMover.Compute('a'#10'b'#10'c', 1, 2, -1, TAtlasLineMoveKind.DuplicateDown, 2, Move));
  Line := 2;
  Character := 1;
  TAtlasLineMover.MapPosition(Move, Line, Character);
  Assert.AreEqual(4, Line);
  Assert.AreEqual(1, Character);
  Assert.IsTrue(TAtlasLineMover.Compute('a'#10'b'#10'c', 1, 2, -1, TAtlasLineMoveKind.DuplicateUp, 2, Move));
  Line := 1;
  TAtlasLineMover.MapPosition(Move, Line, Character);
  Assert.AreEqual(1, Line);
end;

procedure TAtlasLineMoveTests.MapsCursorWithIndent;
var
  Move: TAtlasLineMove;
  Line, Character: Integer;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(Loop, 5, 5, 5, TAtlasLineMoveKind.MoveUp, 2, Move));
  Line := 5;
  Character := 6;
  TAtlasLineMover.MapPosition(Move, Line, Character);
  Assert.AreEqual(4, Line);
  Assert.AreEqual(4, Character);
  // Zeilen außerhalb des Blocks bleiben.
  Line := 1;
  Character := 3;
  TAtlasLineMover.MapPosition(Move, Line, Character);
  Assert.AreEqual(1, Line);
  Assert.AreEqual(3, Character);
end;

procedure TAtlasLineMoveTests.MovesMethodWithCommentsDown;
var
  Move: TAtlasLineMove;
begin
  // Cursor auf dem Kopf von A, ohne Markierung: A samt Kommentar wandert hinter B samt Kommentaren.
  Assert.IsTrue(TAtlasLineMover.Compute(Methods, 5, 5, 5, TAtlasLineMoveKind.MoveDown, 2, Move));
  Assert.IsTrue(Move.Method);
  Assert.AreEqual(
    'implementation'#10 +
    #10 +
    '{ TFoo }'#10 +
    #10 +
    '// Zweite'#10 +
    '{ über zwei'#10 +
    '  Zeilen }'#10 +
    'procedure TFoo.B(AValue: Integer);'#10 +
    'begin'#10 +
    '  Y;'#10 +
    'end;'#10 +
    #10 +
    '/// Erste'#10 +
    'procedure TFoo.A;'#10 +
    'begin'#10 +
    '  X;'#10 +
    'end;'#10 +
    #10 +
    'end.', Joined(TAtlasLineMover.Apply(Methods.Split([#10]), Move)));
  Assert.AreEqual(4, Move.OldFirstLine);
  Assert.AreEqual(12, Move.FirstLine);
  Assert.AreEqual(16, Move.LastLine);
  Assert.AreEqual(8, Move.LineShift);
  // Hinter B gibt es keine Methode mehr.
  Assert.AreEqual('-', Moved(Methods, 13, 13, 13, TAtlasLineMoveKind.MoveDown));
end;

procedure TAtlasLineMoveTests.MovesMethodUp;
var
  Move: TAtlasLineMove;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(Methods, 13, 13, 13, TAtlasLineMoveKind.MoveUp, 2, Move));
  Assert.AreEqual(Moved(Methods, 5, 5, 5, TAtlasLineMoveKind.MoveDown),
    Joined(TAtlasLineMover.Apply(Methods.Split([#10]), Move)));
  Assert.AreEqual(4, Move.FirstLine);
  Assert.AreEqual(-6, Move.LineShift);
  Assert.IsFalse(TAtlasLineMover.Compute(Methods, 5, 5, 5, TAtlasLineMoveKind.MoveUp, 2, Move), 'vor A keine Methode');
  Assert.IsTrue(Move.Method, 'Grund für die Meldung');
end;

procedure TAtlasLineMoveTests.MethodNeedsNeighbourWithoutCodeBetween;
const
  WithVar =
    'implementation'#10 +
    'procedure A;'#10 +
    'begin'#10 +
    'end;'#10 +
    'var'#10 +
    '  G: Integer;'#10 +
    'procedure B;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  WithDirective =
    'implementation'#10 +
    'procedure A;'#10 +
    'begin'#10 +
    'end;'#10 +
    '{$IFDEF X}'#10 +
    'procedure B;'#10 +
    'begin'#10 +
    'end;'#10 +
    '{$ENDIF}'#10 +
    'end.';
begin
  Assert.AreEqual('-', Moved(WithVar, 1, 1, 1, TAtlasLineMoveKind.MoveDown));
  Assert.AreEqual('-', Moved(WithDirective, 1, 1, 1, TAtlasLineMoveKind.MoveDown));
  // Mit Markierung gilt die Zeile, nicht die Methode.
  Assert.AreEqual('implementation'#10'begin'#10'  procedure A;', Copy(Moved(WithVar, 1, 1, -1,
    TAtlasLineMoveKind.MoveDown), 1, 35));
end;

procedure TAtlasLineMoveTests.CursorInBodyMovesLineOnly;
var
  Move: TAtlasLineMove;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(Methods, 7, 7, 7, TAtlasLineMoveKind.MoveDown, 2, Move));
  Assert.IsFalse(Move.Method);
  Assert.AreEqual(2, Move.OldCount);
  Assert.IsFalse(TAtlasLineMover.Compute('a', 0, 0, 0, TAtlasLineMoveKind.MoveDown, 2, Move));
  Assert.IsFalse(Move.Method);
end;

procedure TAtlasLineMoveTests.DifferenceReplacesWholeLines;
var
  Start, OldLength: Integer;
  Insert: string;
begin
  Assert.IsTrue(TAtlasLineMover.Difference('a'#13#10'b1'#13#10'c'#13#10'd', 'a'#13#10'c'#13#10'b1'#13#10'd', Start,
    OldLength, Insert));
  Assert.AreEqual(3, Start);
  Assert.AreEqual(7, OldLength);
  Assert.AreEqual('c'#13#10'b1'#13#10, Insert);
  // Gleicher Anfang mitten in der Zeile: ab dem Zeilenanfang.
  Assert.IsTrue(TAtlasLineMover.Difference('ab'#10'x', 'ac'#10'x', Start, OldLength, Insert));
  Assert.AreEqual(0, Start);
  Assert.AreEqual(3, OldLength);
  Assert.AreEqual('ac'#10, Insert);
  // Neue Zeile am Ende ohne Zeilenumbruch.
  Assert.IsTrue(TAtlasLineMover.Difference('a'#10'b', 'a'#10'b'#10'b', Start, OldLength, Insert));
  Assert.AreEqual(2, Start);
  Assert.AreEqual(0, OldLength);
  Assert.AreEqual('b'#10, Insert);
  Assert.IsFalse(TAtlasLineMover.Difference('a', 'a', Start, OldLength, Insert));
end;

procedure TAtlasLineMoveTests.CommentOnlyTextWithoutDirectives;
begin
  Assert.IsTrue(TAtlasLineMover.IsCommentOnly('  // x'#10'{ a'#10' b }'#10'(* c *)'#10));
  Assert.IsTrue(TAtlasLineMover.IsCommentOnly(''));
  Assert.IsFalse(TAtlasLineMover.IsCommentOnly('{$R *.dfm}'));
  Assert.IsFalse(TAtlasLineMover.IsCommentOnly('(*$X*)'));
  Assert.IsFalse(TAtlasLineMover.IsCommentOnly('{ offen'));
  Assert.IsFalse(TAtlasLineMover.IsCommentOnly('// x'#10'var'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLineMoveTests);

end.
