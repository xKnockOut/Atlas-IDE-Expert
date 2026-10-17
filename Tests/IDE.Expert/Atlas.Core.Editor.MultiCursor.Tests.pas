unit Atlas.Core.Editor.MultiCursor.Tests;

// Tests für mehrere Einfügemarken (#589): Akzeptanzfälle (drei Vorkommen
// umbenennen, Semikolon an fünf Zeilenenden, dreizeilige Zwischenablage an
// drei Marken), Zusammenlegen, Alt+Klick, Bewegen, Marken darüber und
// darunter, nächstes Vorkommen und Überspringen, Bearbeiten, Einfügen,
// Kopieren, fremde Änderungen und gespiegelte Änderungen der IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMultiCursorTests = class
  public
    [Test]
    procedure RenamesThreeOccurrences;
    [Test]
    procedure SemicolonAtFiveLineEnds;
    [Test]
    procedure PastesOneLinePerCaret;
    [Test]
    procedure PastesWholeTextOnOtherCount;
    [Test]
    procedure MergeRemovesDuplicatesAndOverlaps;
    [Test]
    procedure MergeKeepsTouchingSelections;
    [Test]
    procedure ToggleAddsAndRemoves;
    [Test]
    procedure MovesLeftAndRight;
    [Test]
    procedure MovesUpAndDownKeepingColumn;
    [Test]
    procedure MovesAcrossTabs;
    [Test]
    procedure MovesToLineStartAndEnd;
    [Test]
    procedure MovesByWords;
    [Test]
    procedure ExtendsAndCollapses;
    [Test]
    procedure MoveMergesCarets;
    [Test]
    procedure AddsCaretsAboveAndBelow;
    [Test]
    procedure LineEndsWithoutSelection;
    [Test]
    procedure NextOccurrenceSelectsWord;
    [Test]
    procedure NextOccurrenceWrapsAndSkipsSelected;
    [Test]
    procedure NextOccurrenceHonoursCaseAndWholeWord;
    [Test]
    procedure SkipsLastOccurrence;
    [Test]
    procedure BackspaceJoinsLines;
    [Test]
    procedure DeleteAtEndAndAcrossLineBreak;
    [Test]
    procedure NewLineKeepsIndent;
    [Test]
    procedure InsertReplacesSelections;
    [Test]
    procedure PastePartsRules;
    [Test]
    procedure CopiesSelectionsInTextOrder;
    [Test]
    procedure ShiftFollowsForeignChanges;
    [Test]
    procedure MirrorsAcceptedSuggestion;
    [Test]
    procedure MirrorIgnoresChangesElsewhere;
    [Test]
    procedure SplitsLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.MultiCursor;

/// <summary>Marken als Text: "Zeile:Zeichen", mit Markierung "Anker>Zeile:Zeichen", getrennt durch "|".</summary>
function Show(const ACarets: TAtlasCarets): string;
var
  Caret: TAtlasCaret;
begin
  Result := '';
  for Caret in ACarets do
  begin
    if Result <> '' then
      Result := Result + '|';
    if Caret.HasSelection then
      Result := Result + Format('%d:%d>', [Caret.AnchorLine, Caret.AnchorCharacter]);
    Result := Result + Format('%d:%d', [Caret.Line, Caret.Character]);
  end;
end;

function Carets(const AItems: array of TAtlasCaret): TAtlasCarets;
var
  Index: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for Index := 0 to High(AItems) do
    Result[Index] := AItems[Index];
end;

function At(ALine, ACharacter: Integer): TAtlasCaret;
begin
  Result := TAtlasCaret.At(ALine, ACharacter);
end;

function Range(AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer): TAtlasCaret;
begin
  Result := TAtlasCaret.Range(AAnchorLine, AAnchorCharacter, ALine, ACharacter);
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := TAtlasMultiCursor.Lines(AText);
end;

{ TAtlasMultiCursorTests }

procedure TAtlasMultiCursorTests.RenamesThreeOccurrences;
const
  Text = 'TKundeFeld = (kfName, kfNameZusatz, kfOrtName)';
var
  Current, Next: TAtlasCarets;
  NewText: string;
begin
  // Doppelklick auf „Name“ in kfName, dann zweimal Strg+D.
  Current := Carets([Range(0, 16, 0, 20)]);
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text), Current, False,
    False, Next)));
  Current := Next;
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text), Current, False,
    False, Next)));
  Assert.AreEqual('0:16>0:20|0:24>0:28|0:41>0:45', Show(Next));
  Assert.IsTrue(TAtlasMultiCursor.Edit(Text, Next, TAtlasCaretEditKind.Insert, 'Bez', NewText, Current));
  Assert.AreEqual('TKundeFeld = (kfBez, kfBezZusatz, kfOrtBez)', NewText);
  Assert.AreEqual('0:19|0:26|0:42', Show(Current));
  // Ein drittes Strg+D findet nichts mehr.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text), Next, False, False,
    Current)));
  Assert.AreEqual(3, Integer(Length(Current)));
end;

procedure TAtlasMultiCursorTests.SemicolonAtFiveLineEnds;
const
  Text = 'a := 1'#13#10'b := 2'#13#10'c := 3'#13#10'd := 4'#13#10'e := 5'#13#10'f := 6';
var
  Ends, After: TAtlasCarets;
  NewText: string;
begin
  // Markierung von Zeile 0 bis zum Anfang von Zeile 5: Zeile 5 zählt nicht.
  Ends := TAtlasMultiCursor.LineEnds(Lines(Text), Range(0, 0, 5, 0));
  Assert.AreEqual('0:6|1:6|2:6|3:6|4:6', Show(Ends));
  Assert.IsTrue(TAtlasMultiCursor.Edit(Text, Ends, TAtlasCaretEditKind.Insert, ';', NewText, After));
  Assert.AreEqual('a := 1;'#13#10'b := 2;'#13#10'c := 3;'#13#10'd := 4;'#13#10'e := 5;'#13#10'f := 6', NewText);
  Assert.AreEqual('0:7|1:7|2:7|3:7|4:7', Show(After));
  // Rückwärts markiert: gleiche Zeilen, erste Zeile ist die Hauptmarke.
  Assert.AreEqual('0:6|1:6', Show(TAtlasMultiCursor.LineEnds(Lines(Text), Range(1, 3, 0, 2))));
end;

procedure TAtlasMultiCursorTests.PastesOneLinePerCaret;
const
  Text = 'x'#13#10'y'#13#10'z';
var
  After: TAtlasCarets;
  NewText: string;
begin
  // Die Hauptmarke steht unten; verteilt wird in Textreihenfolge.
  Assert.IsTrue(TAtlasMultiCursor.Paste(Text, Carets([At(2, 1), At(0, 1), At(1, 1)]), '1'#13#10'2'#13#10'3'#13#10,
    NewText, After));
  Assert.AreEqual('x1'#13#10'y2'#13#10'z3', NewText);
  Assert.AreEqual('2:2|0:2|1:2', Show(After));
end;

procedure TAtlasMultiCursorTests.PastesWholeTextOnOtherCount;
const
  Text = 'x'#13#10'y'#13#10'z';
var
  After: TAtlasCarets;
  NewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Paste(Text, Carets([At(0, 1), At(2, 1)]), 'a'#10'b'#10'c', NewText, After));
  Assert.AreEqual('xa'#13#10'b'#13#10'c'#13#10'y'#13#10'za'#13#10'b'#13#10'c', NewText);
  Assert.AreEqual('2:1|6:1', Show(After));
  // Eine Marke: der Text unverändert, auch mit abschließendem Umbruch.
  Assert.IsTrue(TAtlasMultiCursor.Paste('ab', Carets([At(0, 1)]), 'X'#10, NewText, After));
  Assert.AreEqual('aX'#10'b', NewText);
  Assert.AreEqual('1:0', Show(After));
end;

procedure TAtlasMultiCursorTests.MergeRemovesDuplicatesAndOverlaps;
var
  Merged: TAtlasCarets;
begin
  Merged := TAtlasMultiCursor.Merge(Carets([At(1, 4), At(0, 2), At(1, 4), At(0, 2)]));
  Assert.AreEqual('1:4|0:2', Show(Merged));
  // Überlappende Markierungen: die frühere bleibt mit der Vereinigung, die Richtung bleibt ihre.
  Merged := TAtlasMultiCursor.Merge(Carets([At(3, 0), Range(0, 8, 0, 2), Range(0, 5, 0, 10), At(0, 9)]));
  Assert.AreEqual('3:0|0:10>0:2', Show(Merged));
  // Eine Marke in einer Markierung geht in ihr auf.
  Merged := TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 6), At(0, 3)]));
  Assert.AreEqual('0:0>0:6', Show(Merged));
  // Ketten werden in mehreren Runden zusammengelegt.
  Merged := TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 3), Range(0, 6, 0, 9), Range(0, 2, 0, 7)]));
  Assert.AreEqual('0:0>0:9', Show(Merged));
end;

procedure TAtlasMultiCursorTests.MergeKeepsTouchingSelections;
begin
  Assert.AreEqual('0:0>0:3|0:3>0:6', Show(TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 3), Range(0, 3, 0, 6)]))));
  // Eine Marke am Rand einer Markierung bleibt eigene Marke.
  Assert.AreEqual('0:0>0:3|0:3', Show(TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 3), At(0, 3)]))));
end;

procedure TAtlasMultiCursorTests.ToggleAddsAndRemoves;
var
  Current: TAtlasCarets;
begin
  Current := TAtlasMultiCursor.Toggle(Carets([At(0, 0)]), 2, 3);
  Assert.AreEqual('0:0|2:3', Show(Current));
  Current := TAtlasMultiCursor.Toggle(Current, 1, 1);
  Assert.AreEqual('0:0|2:3|1:1', Show(Current));
  Current := TAtlasMultiCursor.Toggle(Current, 2, 3);
  Assert.AreEqual('0:0|1:1', Show(Current));
  // Die Hauptmarke wird nie entfernt.
  Assert.AreEqual('0:0|1:1', Show(TAtlasMultiCursor.Toggle(Current, 0, 0)));
  Assert.AreEqual('4:2', Show(TAtlasMultiCursor.Toggle(nil, 4, 2)));
end;

procedure TAtlasMultiCursorTests.MovesLeftAndRight;
const
  Text = 'ab'#10'cd';
begin
  Assert.AreEqual('0:1|0:2', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 2), At(1, 0)]),
    TAtlasCaretMove.Left, False, 4)));
  Assert.AreEqual('1:0|1:2', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 2), At(1, 2)]),
    TAtlasCaretMove.Right, False, 4)));
  // Am Dateianfang bzw. -ende bleibt die Marke.
  Assert.AreEqual('0:0', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 0)]), TAtlasCaretMove.Left, False,
    4)));
  Assert.AreEqual('1:2', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(1, 2)]), TAtlasCaretMove.Right, False,
    4)));
end;

procedure TAtlasMultiCursorTests.MovesUpAndDownKeepingColumn;
const
  Text = 'abcdef'#10'ab'#10'abcdefgh';
var
  Current: TAtlasCarets;
begin
  Current := TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 5)]), TAtlasCaretMove.Down, False, 4);
  Assert.AreEqual('1:2', Show(Current));
  Assert.AreEqual(5, Current[0].Column);
  // Die gemerkte Spalte gilt in der nächsten Zeile wieder.
  Current := TAtlasMultiCursor.Move(Lines(Text), Current, TAtlasCaretMove.Down, False, 4);
  Assert.AreEqual('2:5', Show(Current));
  // Letzte Zeile: ans Ende; erste Zeile: an den Anfang.
  Assert.AreEqual('2:8', Show(TAtlasMultiCursor.Move(Lines(Text), Current, TAtlasCaretMove.Down, False, 4)));
  Assert.AreEqual('0:0', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 3)]), TAtlasCaretMove.Up, False,
    4)));
  Assert.AreEqual('1:2', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(2, 3)]), TAtlasCaretMove.Up, False,
    4)));
  // Eine andere Bewegung vergisst die Spalte.
  Current := TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 5)]), TAtlasCaretMove.Down, False, 4);
  Current := TAtlasMultiCursor.Move(Lines(Text), Current, TAtlasCaretMove.Left, False, 4);
  Assert.AreEqual(-1, Current[0].Column);
end;

procedure TAtlasMultiCursorTests.MovesAcrossTabs;
const
  Text = #9'x'#10'abcdef';
begin
  // Tab bis Spalte 4: "x" steht in Spalte 4, in der Zeile darunter Zeichen 4.
  Assert.AreEqual('1:4', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 1)]), TAtlasCaretMove.Down, False,
    4)));
  // Spalte 3 liegt im Tab: nach oben vor das Tab-Ende, also Zeichen 1.
  Assert.AreEqual('0:1', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(1, 3)]), TAtlasCaretMove.Up, False,
    4)));
  Assert.AreEqual('0:1', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(1, 2)]), TAtlasCaretMove.Up, False,
    2)));
end;

procedure TAtlasMultiCursorTests.MovesToLineStartAndEnd;
const
  Text = '  abc'#10'de';
begin
  Assert.AreEqual('0:0|1:0', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 3), At(1, 2)]),
    TAtlasCaretMove.LineStart, False, 4)));
  Assert.AreEqual('0:5|1:2', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 3), At(1, 0)]),
    TAtlasCaretMove.LineEnd, False, 4)));
end;

procedure TAtlasMultiCursorTests.MovesByWords;
const
  Text = 'Foo := Bar(1);'#10'  Baz';
var
  L: TArray<string>;
begin
  L := Lines(Text);
  Assert.AreEqual('0:4', Show(TAtlasMultiCursor.Move(L, Carets([At(0, 0)]), TAtlasCaretMove.WordRight, False, 4)));
  Assert.AreEqual('0:7', Show(TAtlasMultiCursor.Move(L, Carets([At(0, 4)]), TAtlasCaretMove.WordRight, False, 4)));
  Assert.AreEqual('0:10', Show(TAtlasMultiCursor.Move(L, Carets([At(0, 7)]), TAtlasCaretMove.WordRight, False, 4)));
  Assert.AreEqual('1:0', Show(TAtlasMultiCursor.Move(L, Carets([At(0, 14)]), TAtlasCaretMove.WordRight, False, 4)));
  Assert.AreEqual('0:7', Show(TAtlasMultiCursor.Move(L, Carets([At(0, 10)]), TAtlasCaretMove.WordLeft, False, 4)));
  Assert.AreEqual('0:4', Show(TAtlasMultiCursor.Move(L, Carets([At(0, 7)]), TAtlasCaretMove.WordLeft, False, 4)));
  Assert.AreEqual('0:0', Show(TAtlasMultiCursor.Move(L, Carets([At(0, 2)]), TAtlasCaretMove.WordLeft, False, 4)));
  Assert.AreEqual('0:14', Show(TAtlasMultiCursor.Move(L, Carets([At(1, 0)]), TAtlasCaretMove.WordLeft, False, 4)));
  Assert.AreEqual('1:0', Show(TAtlasMultiCursor.Move(L, Carets([At(1, 2)]), TAtlasCaretMove.WordLeft, False, 4)));
end;

procedure TAtlasMultiCursorTests.ExtendsAndCollapses;
const
  Text = 'abcdef'#10'ghijkl';
var
  Current: TAtlasCarets;
begin
  Current := TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 2), At(1, 2)]), TAtlasCaretMove.Right, True, 4);
  Current := TAtlasMultiCursor.Move(Lines(Text), Current, TAtlasCaretMove.Right, True, 4);
  Assert.AreEqual('0:2>0:4|1:2>1:4', Show(Current));
  // Ohne Umschalt: Links an den Anfang, Rechts an das Ende der Markierung.
  Assert.AreEqual('0:2|1:2', Show(TAtlasMultiCursor.Move(Lines(Text), Current, TAtlasCaretMove.Left, False, 4)));
  Assert.AreEqual('0:4|1:4', Show(TAtlasMultiCursor.Move(Lines(Text), Current, TAtlasCaretMove.Right, False, 4)));
  // Andere Bewegungen gehen vom Caret aus und heben die Markierung auf.
  Assert.AreEqual('0:6|1:6', Show(TAtlasMultiCursor.Move(Lines(Text), Current, TAtlasCaretMove.LineEnd, False, 4)));
  Assert.AreEqual('0:2>0:0|1:2>1:0', Show(TAtlasMultiCursor.Move(Lines(Text), Carets([At(0, 2), At(1, 2)]),
    TAtlasCaretMove.LineStart, True, 4)));
end;

procedure TAtlasMultiCursorTests.MoveMergesCarets;
begin
  Assert.AreEqual('0:0', Show(TAtlasMultiCursor.Move(Lines('abc'), Carets([At(0, 1), At(0, 2)]),
    TAtlasCaretMove.LineStart, False, 4)));
  // Erweiterte Markierungen, die sich überlappen, werden eine.
  Assert.AreEqual('0:0>0:3', Show(TAtlasMultiCursor.Move(Lines('abc'),
    Carets([Range(0, 0, 0, 1), Range(0, 2, 0, 1)]), TAtlasCaretMove.LineEnd, True, 4)));
end;

procedure TAtlasMultiCursorTests.AddsCaretsAboveAndBelow;
const
  Text = 'abcdef'#10'ab'#10'abcdef'#10#9'x';
var
  Current, Next: TAtlasCarets;
begin
  // Ein- und Ausgabe sind getrennte Variablen: out leert die Variable vor dem Aufruf.
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(Text), Carets([At(0, 4)]), False, 4, Current));
  Assert.AreEqual('0:4|1:2', Show(Current));
  // Von der untersten Marke aus, mit ihrer gemerkten Spalte.
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(Text), Current, False, 4, Next));
  Assert.AreEqual('0:4|1:2|2:4', Show(Next));
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(Text), Next, False, 4, Current));
  Assert.AreEqual('0:4|1:2|2:4|3:1', Show(Current));
  Assert.IsFalse(TAtlasMultiCursor.AddVertical(Lines(Text), Current, False, 4, Next));
  Assert.AreEqual(Show(Current), Show(Next));
  Assert.IsFalse(TAtlasMultiCursor.AddVertical(Lines(Text), Current, True, 4, Next));
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(Text), Carets([At(2, 1)]), True, 4, Current));
  Assert.AreEqual('2:1|1:1', Show(Current));
  Assert.IsFalse(TAtlasMultiCursor.AddVertical(Lines(Text), nil, True, 4, Current));
end;

procedure TAtlasMultiCursorTests.LineEndsWithoutSelection;
begin
  Assert.AreEqual('1:2', Show(TAtlasMultiCursor.LineEnds(Lines('abc'#10'de'), At(1, 0))));
  // Markierung innerhalb einer Zeile: eine Marke.
  Assert.AreEqual('0:3', Show(TAtlasMultiCursor.LineEnds(Lines('abc'#10'de'), Range(0, 0, 0, 2))));
end;

procedure TAtlasMultiCursorTests.NextOccurrenceSelectsWord;
const
  Text = 'Foo := Bar + Bar;';
var
  Current: TAtlasCarets;
begin
  Assert.AreEqual(Ord(TAtlasOccurrence.WordSelected), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([At(0, 8)]), False, False, Current)));
  Assert.AreEqual('0:7>0:10', Show(Current));
  // Direkt hinter dem Wort zählt es auch.
  Assert.AreEqual(Ord(TAtlasOccurrence.WordSelected), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([At(0, 3)]), False, False, Current)));
  Assert.AreEqual('0:0>0:3', Show(Current));
  // Kein Wort am Caret.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text), Carets([At(0, 5)]),
    False, False, Current)));
  Assert.AreEqual('0:5', Show(Current));
end;

procedure TAtlasMultiCursorTests.NextOccurrenceWrapsAndSkipsSelected;
const
  Text = 'Bar'#10'x := Bar;'#10'Bar';
var
  Current, Next: TAtlasCarets;
begin
  // Ab der letzten Zeile geht es am Dateiende von vorn weiter.
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([Range(2, 0, 2, 3)]), False, False, Current)));
  Assert.AreEqual('2:0>2:3|0:0>0:3', Show(Current));
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text), Current, False,
    False, Next)));
  Assert.AreEqual('2:0>2:3|0:0>0:3|1:5>1:8', Show(Next));
  // Alle markiert: nichts mehr, die Marken bleiben.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text), Next, False,
    False, Current)));
  Assert.AreEqual(3, Integer(Length(Current)));
  // Mehrzeilige Markierung sucht nicht.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([Range(0, 0, 1, 2)]), False, False, Current)));
end;

procedure TAtlasMultiCursorTests.NextOccurrenceHonoursCaseAndWholeWord;
const
  Text = 'name := Name + Namen;';
var
  Current: TAtlasCarets;
begin
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([Range(0, 0, 0, 4)]), False, False, Current)));
  Assert.AreEqual('0:0>0:4|0:8>0:12', Show(Current));
  // Groß-/Kleinschreibung beachten: „Name“ und „Namen“ passen nicht.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([Range(0, 0, 0, 4)]), True, False, Current)));
  Assert.AreEqual('0:0>0:4', Show(Current));
  // Ganze Wörter: „Namen“ fällt weg, „Name“ bleibt.
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([Range(0, 8, 0, 12)]), False, True, Current)));
  Assert.AreEqual('0:8>0:12|0:0>0:4', Show(Current));
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(Text),
    Carets([Range(0, 8, 0, 12)]), False, False, Current)));
  Assert.AreEqual('0:8>0:12|0:15>0:19', Show(Current));
end;

procedure TAtlasMultiCursorTests.SkipsLastOccurrence;
const
  Text = 'a b a b a';
var
  Current: TAtlasCarets;
begin
  Assert.IsTrue(TAtlasMultiCursor.SkipOccurrence(Lines(Text), Carets([Range(0, 0, 0, 1), Range(0, 4, 0, 5)]), False,
    False, Current));
  Assert.AreEqual('0:0>0:1|0:8>0:9', Show(Current));
  Assert.IsFalse(TAtlasMultiCursor.SkipOccurrence(Lines(Text), Carets([Range(0, 0, 0, 1)]), False, False, Current));
  Assert.AreEqual('0:0>0:1', Show(Current));
end;

procedure TAtlasMultiCursorTests.BackspaceJoinsLines;
var
  After: TAtlasCarets;
  NewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab'#13#10'cd'#13#10'ef', Carets([At(1, 0), At(2, 1)]),
    TAtlasCaretEditKind.Backspace, '', NewText, After));
  Assert.AreEqual('abcd'#13#10'f', NewText);
  Assert.AreEqual('0:2|1:0', Show(After));
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab'#10'cd', Carets([At(1, 0)]), TAtlasCaretEditKind.Backspace, '', NewText,
    After));
  Assert.AreEqual('abcd', NewText);
  Assert.AreEqual('0:2', Show(After));
  // Am Dateianfang ändert sich nichts.
  Assert.IsFalse(TAtlasMultiCursor.Edit('ab', Carets([At(0, 0)]), TAtlasCaretEditKind.Backspace, '', NewText,
    After));
  Assert.AreEqual('ab', NewText);
end;

procedure TAtlasMultiCursorTests.DeleteAtEndAndAcrossLineBreak;
var
  After: TAtlasCarets;
  NewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab'#13#10'cd', Carets([At(0, 2), At(1, 2)]), TAtlasCaretEditKind.Delete, '',
    NewText, After));
  Assert.AreEqual('abcd', NewText);
  Assert.AreEqual('0:2|0:4', Show(After));
  Assert.IsFalse(TAtlasMultiCursor.Edit('ab', Carets([At(0, 2)]), TAtlasCaretEditKind.Delete, '', NewText, After));
  Assert.IsTrue(TAtlasMultiCursor.Edit('abcd', Carets([At(0, 0), At(0, 2)]), TAtlasCaretEditKind.Delete, '',
    NewText, After));
  Assert.AreEqual('bd', NewText);
  Assert.AreEqual('0:0|0:1', Show(After));
end;

procedure TAtlasMultiCursorTests.NewLineKeepsIndent;
var
  After: TAtlasCarets;
  NewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('  ab'#13#10#9'cd', Carets([At(0, 3), At(1, 3)]),
    TAtlasCaretEditKind.NewLine, '', NewText, After));
  Assert.AreEqual('  a'#13#10'  b'#13#10#9'cd'#13#10#9, NewText);
  Assert.AreEqual('1:2|3:1', Show(After));
  // Marke im Einzug: höchstens bis zur Marke.
  Assert.IsTrue(TAtlasMultiCursor.Edit('    x', Carets([At(0, 2)]), TAtlasCaretEditKind.NewLine, '', NewText, After));
  Assert.AreEqual('  '#10'    x', NewText);
  Assert.AreEqual('1:2', Show(After));
end;

procedure TAtlasMultiCursorTests.InsertReplacesSelections;
var
  After: TAtlasCarets;
  NewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('one two'#10'three', Carets([Range(1, 5, 1, 0), At(0, 3), Range(0, 4, 0, 7)]),
    TAtlasCaretEditKind.Insert, 'X', NewText, After));
  Assert.AreEqual('oneX X'#10'X', NewText);
  Assert.AreEqual('1:1|0:4|0:6', Show(After));
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab', Carets([Range(0, 0, 0, 1), At(0, 2)]), TAtlasCaretEditKind.Backspace,
    '', NewText, After));
  Assert.AreEqual('', NewText);
  Assert.AreEqual('0:0', Show(After));
  Assert.IsFalse(TAtlasMultiCursor.Edit('ab', Carets([At(0, 1)]), TAtlasCaretEditKind.Insert, '', NewText, After));
end;

procedure TAtlasMultiCursorTests.PastePartsRules;
var
  Parts: TArray<string>;
begin
  Parts := TAtlasMultiCursor.PasteParts('a'#13#10'b'#13#10, 2);
  Assert.AreEqual(2, Integer(Length(Parts)));
  Assert.AreEqual('a', Parts[0]);
  Assert.AreEqual('b', Parts[1]);
  Parts := TAtlasMultiCursor.PasteParts('a'#10'b'#10'c', 2);
  Assert.AreEqual(1, Integer(Length(Parts)));
  Assert.AreEqual('a'#10'b'#10'c', Parts[0]);
  // Ein leerer Teil in der Mitte zählt.
  Parts := TAtlasMultiCursor.PasteParts('a'#10#10'c', 3);
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual('', Parts[1]);
  Parts := TAtlasMultiCursor.PasteParts('', 1);
  Assert.AreEqual(1, Integer(Length(Parts)));
  Parts := nil;
end;

procedure TAtlasMultiCursorTests.CopiesSelectionsInTextOrder;
const
  Text = 'alpha beta'#13#10'gamma';
begin
  Assert.AreEqual('alpha'#13#10'beta'#13#10'gam', TAtlasMultiCursor.SelectedText(Text,
    Carets([Range(0, 6, 0, 10), Range(1, 3, 1, 0), Range(0, 0, 0, 5)]), #13#10));
  Assert.AreEqual('alpha'#10'beta'#10'gam', TAtlasMultiCursor.SelectedText(Text,
    Carets([Range(0, 6, 0, 10), Range(1, 3, 1, 0), Range(0, 0, 0, 5)]), #10));
  // Marken ohne Markierung zählen nicht; ohne Markierung ''.
  Assert.AreEqual('beta', TAtlasMultiCursor.SelectedText(Text, Carets([At(1, 1), Range(0, 6, 0, 10)]), #10));
  Assert.AreEqual('', TAtlasMultiCursor.SelectedText(Text, Carets([At(1, 1), At(0, 1)]), #10));
end;

procedure TAtlasMultiCursorTests.ShiftFollowsForeignChanges;
begin
  // Einfügen vor einer Marke in derselben Zeile, eine Marke davor bleibt.
  Assert.AreEqual('0:1|0:7', Show(TAtlasMultiCursor.Shift('abcdef', 'abXXcdef', Carets([At(0, 1), At(0, 5)]))));
  // Eingefügte Zeile verschiebt die Marken dahinter.
  Assert.AreEqual('0:1|2:1', Show(TAtlasMultiCursor.Shift('ab'#10'cd', 'ab'#10'neu'#10'cd',
    Carets([At(0, 1), At(1, 1)]))));
  // Marke im gelöschten Bereich steht hinter dem Eingefügten.
  Assert.AreEqual('0:3|0:1', Show(TAtlasMultiCursor.Shift('abcdef', 'abZef', Carets([At(0, 3), At(0, 1)]))));
  // Markierungen rücken mit, auch eine Marke genau an der Einfügestelle.
  Assert.AreEqual('1:0>1:2', Show(TAtlasMultiCursor.Shift('ab', 'x'#10'ab', Carets([Range(0, 0, 0, 2)]))));
  Assert.AreEqual('0:1', Show(TAtlasMultiCursor.Shift('ab', 'ab', Carets([At(0, 1)]))));
end;

procedure TAtlasMultiCursorTests.MirrorsAcceptedSuggestion;
const
  Old = 'kfNa := 1;'#13#10'kfNa := 2;'#13#10'kfNa := 3;';
var
  After: TAtlasCarets;
  NewText: string;
begin
  // Getippt wurde „Na“ an drei Marken; die IDE übernimmt „Name“ an der Hauptmarke.
  Assert.IsTrue(TAtlasMultiCursor.Mirror(Old, 'kfNa := 1;'#13#10'kfName := 2;'#13#10'kfNa := 3;',
    Carets([At(1, 4), At(0, 4), At(2, 4)]), NewText, After));
  Assert.AreEqual('kfName := 1;'#13#10'kfName := 2;'#13#10'kfName := 3;', NewText);
  Assert.AreEqual('1:6|0:6|2:6', Show(After));
  // Ersetzt die IDE das Präfix (gelöscht und eingefügt), gilt das an jeder Marke.
  Assert.IsTrue(TAtlasMultiCursor.Mirror('Na'#10'Na', 'Na'#10'Nummer', Carets([At(1, 2), At(0, 2)]), NewText,
    After));
  Assert.AreEqual('Nummer'#10'Nummer', NewText);
  Assert.AreEqual('1:6|0:6', Show(After));
  // Marken mit Markierung bleiben unberührt und rücken nur mit.
  Assert.IsTrue(TAtlasMultiCursor.Mirror('ab'#10'cd', 'abX'#10'cd', Carets([At(0, 2), Range(1, 0, 1, 2)]), NewText,
    After));
  Assert.AreEqual('abX'#10'cd', NewText);
  Assert.AreEqual('0:3|1:0>1:2', Show(After));
end;

procedure TAtlasMultiCursorTests.MirrorIgnoresChangesElsewhere;
var
  After: TAtlasCarets;
  NewText: string;
begin
  Assert.IsFalse(TAtlasMultiCursor.Mirror('abc'#10'def', 'abc'#10'dXef', Carets([At(0, 1), At(1, 3)]), NewText,
    After));
  Assert.AreEqual('abc'#10'dXef', NewText);
  // Gelöschter Zeilenumbruch: nicht spiegeln.
  Assert.IsFalse(TAtlasMultiCursor.Mirror('ab'#10'cd', 'abcd', Carets([At(0, 2), At(1, 1)]), NewText, After));
  // Hauptmarke mit Markierung oder keine Änderung.
  Assert.IsFalse(TAtlasMultiCursor.Mirror('ab', 'aXb', Carets([Range(0, 0, 0, 1)]), NewText, After));
  Assert.IsFalse(TAtlasMultiCursor.Mirror('ab', 'ab', Carets([At(0, 1)]), NewText, After));
end;

procedure TAtlasMultiCursorTests.SplitsLines;
var
  Parts: TArray<string>;
begin
  Parts := TAtlasMultiCursor.Lines('a'#13#10'b'#10#10'c'#13#10);
  Assert.AreEqual(5, Integer(Length(Parts)));
  Assert.AreEqual('a', Parts[0]);
  Assert.AreEqual('b', Parts[1]);
  Assert.AreEqual('', Parts[2]);
  Assert.AreEqual('c', Parts[3]);
  Assert.AreEqual('', Parts[4]);
  Assert.AreEqual(1, Integer(Length(TAtlasMultiCursor.Lines(''))));
  Assert.AreEqual(#13#10, TAtlasMultiCursor.LineBreakOf('a'#10'b'#13#10));
  Assert.AreEqual(#10, TAtlasMultiCursor.LineBreakOf('a'#10'b'));
  Parts := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMultiCursorTests);

end.
