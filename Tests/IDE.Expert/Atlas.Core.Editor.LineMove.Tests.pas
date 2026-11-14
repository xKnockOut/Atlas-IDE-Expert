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
  cLoop =
    'procedure P;'#10 +
    'begin'#10 +
    '  A;'#10 +
    '  while X do'#10 +
    '  begin'#10 +
    '    B;'#10 +
    '  end;'#10 +
    'end;';

  cMethods =
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
  mMove: TAtlasLineMove;
begin
  Result := '-';
  if TAtlasLineMover.Compute(AText, TAtlasLineSelection.Create(AFirst, ALast, AMethodLine), AKind, 2, mMove) then
  begin
    Result := Joined(TAtlasLineMover.Apply(AText.Split([#10]), mMove));
  end;
end;

{ TAtlasLineMoveTests }

procedure TAtlasLineMoveTests.SwapsWithNeighbour;
begin
  Assert.AreEqual('b'#10'a'#10'c', Moved('a'#10'b'#10'c', 0, 0, 0, TAtlasLineMoveKind.MoveDown));
  Assert.AreEqual('a'#10'c'#10'b', Moved('a'#10'b'#10'c', 2, 2, 2, TAtlasLineMoveKind.MoveUp));
end;

procedure TAtlasLineMoveTests.IndentFollowsBlockDepth;
var
  mText: string;
begin
  // "A;" wandert abwärts: über "while" ohne Änderung, über "begin" eine Ebene tiefer, über "end;" zurück.
  mText := Moved(cLoop, 2, 2, 2, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual('  A;', mText.Split([#10])[3]);
  mText := Moved(mText, 3, 3, 3, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual('    A;', mText.Split([#10])[4]);
  mText := Moved(mText, 4, 4, 4, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual('    A;', mText.Split([#10])[5]);
  mText := Moved(mText, 5, 5, 5, TAtlasLineMoveKind.MoveDown);
  Assert.AreEqual(
    'procedure P;'#10 +
    'begin'#10 +
    '  while X do'#10 +
    '  begin'#10 +
    '    B;'#10 +
    '  end;'#10 +
    '  A;'#10 +
    'end;', mText);
end;

procedure TAtlasLineMoveTests.MovingUpLeavesBlock;
var
  mText: string;
begin
  // "B;" aufwärts über "begin" eine Ebene höher; wieder abwärts eine tiefer.
  mText := Moved(cLoop, 5, 5, 5, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('  B;', mText.Split([#10])[4]);
  Assert.AreEqual(cLoop, Moved(mText, 4, 4, 4, TAtlasLineMoveKind.MoveDown));
  // Ohne Blockgrenze bleibt der Einzug, auch für "end;" selbst.
  mText := Moved(cLoop, 6, 6, 6, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('  end;', mText.Split([#10])[5]);
  // Aufwärts über "end;" in den Block hinein.
  mText := Moved(cLoop + #10'C;', 8, 8, 8, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('  C;', mText.Split([#10])[7], 'über "end;" der Routine');
  mText := Moved(mText, 7, 7, 7, TAtlasLineMoveKind.MoveUp);
  Assert.AreEqual('    C;', mText.Split([#10])[6], 'über "end;" der Schleife');
end;

procedure TAtlasLineMoveTests.FinallyAndElseKeepIndent;
const
  cTryText =
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
  Assert.AreEqual('    A;', Moved(cTryText, 2, 2, 2, TAtlasLineMoveKind.MoveDown).Split([#10])[3]);
  Assert.AreEqual('    D;', Moved(cTryText, 10, 10, 10, TAtlasLineMoveKind.MoveUp).Split([#10])[9]);
  Assert.AreEqual('    C;', Moved(cTryText, 8, 8, 8, TAtlasLineMoveKind.MoveDown).Split([#10])[9]);
end;

procedure TAtlasLineMoveTests.MovesSelectionAndKeepsEmptyLines;
const
  cText =
    'begin'#10 +
    '  A;'#10 +
    ''#10 +
    '  B;'#10 +
    '  with X do'#10 +
    '  begin'#10 +
    '  end;'#10 +
    'end;';
var
  mMove: TAtlasLineMove;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(Moved(cText, 1, 3, -1, TAtlasLineMoveKind.MoveDown),
    TAtlasLineSelection.Create(2, 4, -1), TAtlasLineMoveKind.MoveDown, 2, mMove));
  Assert.AreEqual(
    'begin'#10 +
    '  with X do'#10 +
    '  begin'#10 +
    '    A;'#10 +
    ''#10 +
    '    B;'#10 +
    '  end;'#10 +
    'end;', Joined(TAtlasLineMover.Apply(Moved(cText, 1, 3, -1, TAtlasLineMoveKind.MoveDown).Split([#10]), mMove)));
  Assert.AreEqual(3, mMove.FirstLine);
  Assert.AreEqual(5, mMove.LastLine);
  Assert.AreEqual(2, mMove.IndentShift[0]);
  Assert.AreEqual(0, mMove.IndentShift[1], 'leere Zeile bleibt leer');
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
  mMove: TAtlasLineMove;
  mLine, mCharacter: Integer;
begin
  Assert.AreEqual('a'#10'b'#10'c'#10'b'#10'c', Moved('a'#10'b'#10'c', 1, 2, -1, TAtlasLineMoveKind.DuplicateDown));
  Assert.AreEqual('a'#10'b'#10'b'#10'c', Moved('a'#10'b'#10'c', 1, 1, 1, TAtlasLineMoveKind.DuplicateUp));
  // Auch an der letzten Zeile; Methodenköpfe werden nur als Zeilen dupliziert.
  Assert.AreEqual('a'#10'b'#10'b', Moved('a'#10'b', 1, 1, 1, TAtlasLineMoveKind.DuplicateDown));
  // Der Cursor wandert mit der Kopie.
  Assert.IsTrue(TAtlasLineMover.Compute('a'#10'b'#10'c', TAtlasLineSelection.Create(1, 2, -1),
    TAtlasLineMoveKind.DuplicateDown, 2, mMove));
  mLine := 2;
  mCharacter := 1;
  TAtlasLineMover.MapPosition(mMove, mLine, mCharacter);
  Assert.AreEqual(4, mLine);
  Assert.AreEqual(1, mCharacter);
  Assert.IsTrue(TAtlasLineMover.Compute('a'#10'b'#10'c', TAtlasLineSelection.Create(1, 2, -1),
    TAtlasLineMoveKind.DuplicateUp, 2, mMove));
  mLine := 1;
  TAtlasLineMover.MapPosition(mMove, mLine, mCharacter);
  Assert.AreEqual(1, mLine);
end;

procedure TAtlasLineMoveTests.MapsCursorWithIndent;
var
  mMove: TAtlasLineMove;
  mLine, mCharacter: Integer;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(cLoop, TAtlasLineSelection.Create(5, 5, 5), TAtlasLineMoveKind.MoveUp, 2,
    mMove));
  mLine := 5;
  mCharacter := 6;
  TAtlasLineMover.MapPosition(mMove, mLine, mCharacter);
  Assert.AreEqual(4, mLine);
  Assert.AreEqual(4, mCharacter);
  // Zeilen außerhalb des Blocks bleiben.
  mLine := 1;
  mCharacter := 3;
  TAtlasLineMover.MapPosition(mMove, mLine, mCharacter);
  Assert.AreEqual(1, mLine);
  Assert.AreEqual(3, mCharacter);
end;

procedure TAtlasLineMoveTests.MovesMethodWithCommentsDown;
var
  mMove: TAtlasLineMove;
begin
  // Cursor auf dem Kopf von A, ohne Markierung: A samt Kommentar wandert hinter B samt Kommentaren.
  Assert.IsTrue(TAtlasLineMover.Compute(cMethods, TAtlasLineSelection.Create(5, 5, 5),
    TAtlasLineMoveKind.MoveDown, 2, mMove));
  Assert.IsTrue(mMove.Method);
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
    'end.', Joined(TAtlasLineMover.Apply(cMethods.Split([#10]), mMove)));
  Assert.AreEqual(4, mMove.OldFirstLine);
  Assert.AreEqual(12, mMove.FirstLine);
  Assert.AreEqual(16, mMove.LastLine);
  Assert.AreEqual(8, mMove.LineShift);
  // Hinter B gibt es keine Methode mehr.
  Assert.AreEqual('-', Moved(cMethods, 13, 13, 13, TAtlasLineMoveKind.MoveDown));
end;

procedure TAtlasLineMoveTests.MovesMethodUp;
var
  mMove: TAtlasLineMove;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(cMethods, TAtlasLineSelection.Create(13, 13, 13),
    TAtlasLineMoveKind.MoveUp, 2, mMove));
  Assert.AreEqual(Moved(cMethods, 5, 5, 5, TAtlasLineMoveKind.MoveDown),
    Joined(TAtlasLineMover.Apply(cMethods.Split([#10]), mMove)));
  Assert.AreEqual(4, mMove.FirstLine);
  Assert.AreEqual(-6, mMove.LineShift);
  Assert.IsFalse(TAtlasLineMover.Compute(cMethods, TAtlasLineSelection.Create(5, 5, 5),
    TAtlasLineMoveKind.MoveUp, 2, mMove), 'vor A keine Methode');
  Assert.IsTrue(mMove.Method, 'Grund für die Meldung');
end;

procedure TAtlasLineMoveTests.MethodNeedsNeighbourWithoutCodeBetween;
const
  cWithVar =
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
  cWithDirective =
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
  Assert.AreEqual('-', Moved(cWithVar, 1, 1, 1, TAtlasLineMoveKind.MoveDown));
  Assert.AreEqual('-', Moved(cWithDirective, 1, 1, 1, TAtlasLineMoveKind.MoveDown));
  // Mit Markierung gilt die Zeile, nicht die Methode.
  Assert.AreEqual('implementation'#10'begin'#10'  procedure A;', Copy(Moved(cWithVar, 1, 1, -1,
    TAtlasLineMoveKind.MoveDown), 1, 35));
end;

procedure TAtlasLineMoveTests.CursorInBodyMovesLineOnly;
var
  mMove: TAtlasLineMove;
begin
  Assert.IsTrue(TAtlasLineMover.Compute(cMethods, TAtlasLineSelection.Create(7, 7, 7),
    TAtlasLineMoveKind.MoveDown, 2, mMove));
  Assert.IsFalse(mMove.Method);
  Assert.AreEqual(2, mMove.OldCount);
  Assert.IsFalse(TAtlasLineMover.Compute('a', TAtlasLineSelection.Create(0, 0, 0),
    TAtlasLineMoveKind.MoveDown, 2, mMove));
  Assert.IsFalse(mMove.Method);
end;

procedure TAtlasLineMoveTests.DifferenceReplacesWholeLines;
var
  mStart, mOldLength: Integer;
  mInsert: string;
begin
  Assert.IsTrue(TAtlasLineMover.Difference('a'#13#10'b1'#13#10'c'#13#10'd', 'a'#13#10'c'#13#10'b1'#13#10'd', mStart,
    mOldLength, mInsert));
  Assert.AreEqual(3, mStart);
  Assert.AreEqual(7, mOldLength);
  Assert.AreEqual('c'#13#10'b1'#13#10, mInsert);
  // Gleicher Anfang mitten in der Zeile: ab dem Zeilenanfang.
  Assert.IsTrue(TAtlasLineMover.Difference('ab'#10'x', 'ac'#10'x', mStart, mOldLength, mInsert));
  Assert.AreEqual(0, mStart);
  Assert.AreEqual(3, mOldLength);
  Assert.AreEqual('ac'#10, mInsert);
  // Neue Zeile am Ende ohne Zeilenumbruch.
  Assert.IsTrue(TAtlasLineMover.Difference('a'#10'b', 'a'#10'b'#10'b', mStart, mOldLength, mInsert));
  Assert.AreEqual(2, mStart);
  Assert.AreEqual(0, mOldLength);
  Assert.AreEqual('b'#10, mInsert);
  Assert.IsFalse(TAtlasLineMover.Difference('a', 'a', mStart, mOldLength, mInsert));
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
