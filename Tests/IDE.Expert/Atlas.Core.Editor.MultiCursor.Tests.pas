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
  mCaret: TAtlasCaret;
begin
  Result := '';
  for mCaret in ACarets do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    if mCaret.HasSelection then
    begin
      Result := Result + Format('%d:%d>', [mCaret.AnchorLine, mCaret.AnchorCharacter]);
    end;
    Result := Result + Format('%d:%d', [mCaret.Line, mCaret.Character]);
  end;
end;

function Carets(const AItems: array of TAtlasCaret): TAtlasCarets;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := AItems[mIndex];
  end;
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
  cText = 'TKundeFeld = (kfName, kfNameZusatz, kfOrtName)';
var
  mCurrent, mNext: TAtlasCarets;
  mNewText: string;
begin
  // Doppelklick auf „Name“ in kfName, dann zweimal Strg+D.
  mCurrent := Carets([Range(0, 16, 0, 20)]);
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText), mCurrent, False,
    False, mNext)));
  mCurrent := mNext;
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText), mCurrent, False,
    False, mNext)));
  Assert.AreEqual('0:16>0:20|0:24>0:28|0:41>0:45', Show(mNext));
  Assert.IsTrue(TAtlasMultiCursor.Edit(cText, mNext, TAtlasCaretEditKind.Insert, 'Bez', mNewText, mCurrent));
  Assert.AreEqual('TKundeFeld = (kfBez, kfBezZusatz, kfOrtBez)', mNewText);
  Assert.AreEqual('0:19|0:26|0:42', Show(mCurrent));
  // Ein drittes Strg+D findet nichts mehr.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText), mNext, False, False,
    mCurrent)));
  Assert.AreEqual(3, Integer(Length(mCurrent)));
end;

procedure TAtlasMultiCursorTests.SemicolonAtFiveLineEnds;
const
  cText = 'a := 1'#13#10'b := 2'#13#10'c := 3'#13#10'd := 4'#13#10'e := 5'#13#10'f := 6';
var
  mEnds, mAfter: TAtlasCarets;
  mNewText: string;
begin
  // Markierung von Zeile 0 bis zum Anfang von Zeile 5: Zeile 5 zählt nicht.
  mEnds := TAtlasMultiCursor.LineEnds(Lines(cText), Range(0, 0, 5, 0));
  Assert.AreEqual('0:6|1:6|2:6|3:6|4:6', Show(mEnds));
  Assert.IsTrue(TAtlasMultiCursor.Edit(cText, mEnds, TAtlasCaretEditKind.Insert, ';', mNewText, mAfter));
  Assert.AreEqual('a := 1;'#13#10'b := 2;'#13#10'c := 3;'#13#10'd := 4;'#13#10'e := 5;'#13#10'f := 6', mNewText);
  Assert.AreEqual('0:7|1:7|2:7|3:7|4:7', Show(mAfter));
  // Rückwärts markiert: gleiche Zeilen, erste Zeile ist die Hauptmarke.
  Assert.AreEqual('0:6|1:6', Show(TAtlasMultiCursor.LineEnds(Lines(cText), Range(1, 3, 0, 2))));
end;

procedure TAtlasMultiCursorTests.PastesOneLinePerCaret;
const
  cText = 'x'#13#10'y'#13#10'z';
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  // Die Hauptmarke steht unten; verteilt wird in Textreihenfolge.
  Assert.IsTrue(TAtlasMultiCursor.Paste(cText, Carets([At(2, 1), At(0, 1), At(1, 1)]), '1'#13#10'2'#13#10'3'#13#10,
    mNewText, mAfter));
  Assert.AreEqual('x1'#13#10'y2'#13#10'z3', mNewText);
  Assert.AreEqual('2:2|0:2|1:2', Show(mAfter));
end;

procedure TAtlasMultiCursorTests.PastesWholeTextOnOtherCount;
const
  cText = 'x'#13#10'y'#13#10'z';
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Paste(cText, Carets([At(0, 1), At(2, 1)]), 'a'#10'b'#10'c', mNewText, mAfter));
  Assert.AreEqual('xa'#13#10'b'#13#10'c'#13#10'y'#13#10'za'#13#10'b'#13#10'c', mNewText);
  Assert.AreEqual('2:1|6:1', Show(mAfter));
  // Eine Marke: der Text unverändert, auch mit abschließendem Umbruch.
  Assert.IsTrue(TAtlasMultiCursor.Paste('ab', Carets([At(0, 1)]), 'X'#10, mNewText, mAfter));
  Assert.AreEqual('aX'#10'b', mNewText);
  Assert.AreEqual('1:0', Show(mAfter));
end;

procedure TAtlasMultiCursorTests.MergeRemovesDuplicatesAndOverlaps;
var
  mMerged: TAtlasCarets;
begin
  mMerged := TAtlasMultiCursor.Merge(Carets([At(1, 4), At(0, 2), At(1, 4), At(0, 2)]));
  Assert.AreEqual('1:4|0:2', Show(mMerged));
  // Überlappende Markierungen: die frühere bleibt mit der Vereinigung, die Richtung bleibt ihre.
  mMerged := TAtlasMultiCursor.Merge(Carets([At(3, 0), Range(0, 8, 0, 2), Range(0, 5, 0, 10), At(0, 9)]));
  Assert.AreEqual('3:0|0:10>0:2', Show(mMerged));
  // Eine Marke in einer Markierung geht in ihr auf.
  mMerged := TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 6), At(0, 3)]));
  Assert.AreEqual('0:0>0:6', Show(mMerged));
  // Ketten werden in mehreren Runden zusammengelegt.
  mMerged := TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 3), Range(0, 6, 0, 9), Range(0, 2, 0, 7)]));
  Assert.AreEqual('0:0>0:9', Show(mMerged));
end;

procedure TAtlasMultiCursorTests.MergeKeepsTouchingSelections;
begin
  Assert.AreEqual('0:0>0:3|0:3>0:6', Show(TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 3), Range(0, 3, 0, 6)]))));
  // Eine Marke am Rand einer Markierung bleibt eigene Marke.
  Assert.AreEqual('0:0>0:3|0:3', Show(TAtlasMultiCursor.Merge(Carets([Range(0, 0, 0, 3), At(0, 3)]))));
end;

procedure TAtlasMultiCursorTests.ToggleAddsAndRemoves;
var
  mCurrent: TAtlasCarets;
begin
  mCurrent := TAtlasMultiCursor.Toggle(Carets([At(0, 0)]), 2, 3);
  Assert.AreEqual('0:0|2:3', Show(mCurrent));
  mCurrent := TAtlasMultiCursor.Toggle(mCurrent, 1, 1);
  Assert.AreEqual('0:0|2:3|1:1', Show(mCurrent));
  mCurrent := TAtlasMultiCursor.Toggle(mCurrent, 2, 3);
  Assert.AreEqual('0:0|1:1', Show(mCurrent));
  // Die Hauptmarke wird nie entfernt.
  Assert.AreEqual('0:0|1:1', Show(TAtlasMultiCursor.Toggle(mCurrent, 0, 0)));
  Assert.AreEqual('4:2', Show(TAtlasMultiCursor.Toggle(nil, 4, 2)));
end;

procedure TAtlasMultiCursorTests.MovesLeftAndRight;
const
  cText = 'ab'#10'cd';
begin
  Assert.AreEqual('0:1|0:2', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 2), At(1, 0)]),
    TAtlasCaretMove.Left, False, 4)));
  Assert.AreEqual('1:0|1:2', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 2), At(1, 2)]),
    TAtlasCaretMove.Right, False, 4)));
  // Am Dateianfang bzw. -ende bleibt die Marke.
  Assert.AreEqual('0:0', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 0)]), TAtlasCaretMove.Left, False,
    4)));
  Assert.AreEqual('1:2', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(1, 2)]), TAtlasCaretMove.Right, False,
    4)));
end;

procedure TAtlasMultiCursorTests.MovesUpAndDownKeepingColumn;
const
  cText = 'abcdef'#10'ab'#10'abcdefgh';
var
  mCurrent: TAtlasCarets;
begin
  mCurrent := TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 5)]), TAtlasCaretMove.Down, False, 4);
  Assert.AreEqual('1:2', Show(mCurrent));
  Assert.AreEqual(5, mCurrent[0].Column);
  // Die gemerkte Spalte gilt in der nächsten Zeile wieder.
  mCurrent := TAtlasMultiCursor.Move(Lines(cText), mCurrent, TAtlasCaretMove.Down, False, 4);
  Assert.AreEqual('2:5', Show(mCurrent));
  // Letzte Zeile: ans Ende; erste Zeile: an den Anfang.
  Assert.AreEqual('2:8', Show(TAtlasMultiCursor.Move(Lines(cText), mCurrent, TAtlasCaretMove.Down, False, 4)));
  Assert.AreEqual('0:0', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 3)]), TAtlasCaretMove.Up, False,
    4)));
  Assert.AreEqual('1:2', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(2, 3)]), TAtlasCaretMove.Up, False,
    4)));
  // Eine andere Bewegung vergisst die Spalte.
  mCurrent := TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 5)]), TAtlasCaretMove.Down, False, 4);
  mCurrent := TAtlasMultiCursor.Move(Lines(cText), mCurrent, TAtlasCaretMove.Left, False, 4);
  Assert.AreEqual(-1, mCurrent[0].Column);
end;

procedure TAtlasMultiCursorTests.MovesAcrossTabs;
const
  cText = #9'x'#10'abcdef';
begin
  // Tab bis Spalte 4: "x" steht in Spalte 4, in der Zeile darunter Zeichen 4.
  Assert.AreEqual('1:4', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 1)]), TAtlasCaretMove.Down, False,
    4)));
  // Spalte 3 liegt im Tab: nach oben vor das Tab-Ende, also Zeichen 1.
  Assert.AreEqual('0:1', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(1, 3)]), TAtlasCaretMove.Up, False,
    4)));
  Assert.AreEqual('0:1', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(1, 2)]), TAtlasCaretMove.Up, False,
    2)));
end;

procedure TAtlasMultiCursorTests.MovesToLineStartAndEnd;
const
  cText = '  abc'#10'de';
begin
  Assert.AreEqual('0:0|1:0', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 3), At(1, 2)]),
    TAtlasCaretMove.LineStart, False, 4)));
  Assert.AreEqual('0:5|1:2', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 3), At(1, 0)]),
    TAtlasCaretMove.LineEnd, False, 4)));
end;

procedure TAtlasMultiCursorTests.MovesByWords;
const
  cText = 'Foo := Bar(1);'#10'  Baz';
var
  L: TArray<string>;
begin
  L := Lines(cText);
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
  cText = 'abcdef'#10'ghijkl';
var
  mCurrent: TAtlasCarets;
begin
  mCurrent := TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 2), At(1, 2)]), TAtlasCaretMove.Right, True, 4);
  mCurrent := TAtlasMultiCursor.Move(Lines(cText), mCurrent, TAtlasCaretMove.Right, True, 4);
  Assert.AreEqual('0:2>0:4|1:2>1:4', Show(mCurrent));
  // Ohne Umschalt: Links an den Anfang, Rechts an das Ende der Markierung.
  Assert.AreEqual('0:2|1:2', Show(TAtlasMultiCursor.Move(Lines(cText), mCurrent, TAtlasCaretMove.Left, False, 4)));
  Assert.AreEqual('0:4|1:4', Show(TAtlasMultiCursor.Move(Lines(cText), mCurrent, TAtlasCaretMove.Right, False, 4)));
  // Andere Bewegungen gehen vom Caret aus und heben die Markierung auf.
  Assert.AreEqual('0:6|1:6', Show(TAtlasMultiCursor.Move(Lines(cText), mCurrent, TAtlasCaretMove.LineEnd, False, 4)));
  Assert.AreEqual('0:2>0:0|1:2>1:0', Show(TAtlasMultiCursor.Move(Lines(cText), Carets([At(0, 2), At(1, 2)]),
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
  cText = 'abcdef'#10'ab'#10'abcdef'#10#9'x';
var
  mCurrent, mNext: TAtlasCarets;
begin
  // Ein- und Ausgabe sind getrennte Variablen: out leert die Variable vor dem Aufruf.
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(cText), Carets([At(0, 4)]), False, 4, mCurrent));
  Assert.AreEqual('0:4|1:2', Show(mCurrent));
  // Von der untersten Marke aus, mit ihrer gemerkten Spalte.
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(cText), mCurrent, False, 4, mNext));
  Assert.AreEqual('0:4|1:2|2:4', Show(mNext));
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(cText), mNext, False, 4, mCurrent));
  Assert.AreEqual('0:4|1:2|2:4|3:1', Show(mCurrent));
  Assert.IsFalse(TAtlasMultiCursor.AddVertical(Lines(cText), mCurrent, False, 4, mNext));
  Assert.AreEqual(Show(mCurrent), Show(mNext));
  Assert.IsFalse(TAtlasMultiCursor.AddVertical(Lines(cText), mCurrent, True, 4, mNext));
  Assert.IsTrue(TAtlasMultiCursor.AddVertical(Lines(cText), Carets([At(2, 1)]), True, 4, mCurrent));
  Assert.AreEqual('2:1|1:1', Show(mCurrent));
  Assert.IsFalse(TAtlasMultiCursor.AddVertical(Lines(cText), nil, True, 4, mCurrent));
end;

procedure TAtlasMultiCursorTests.LineEndsWithoutSelection;
begin
  Assert.AreEqual('1:2', Show(TAtlasMultiCursor.LineEnds(Lines('abc'#10'de'), At(1, 0))));
  // Markierung innerhalb einer Zeile: eine Marke.
  Assert.AreEqual('0:3', Show(TAtlasMultiCursor.LineEnds(Lines('abc'#10'de'), Range(0, 0, 0, 2))));
end;

procedure TAtlasMultiCursorTests.NextOccurrenceSelectsWord;
const
  cText = 'Foo := Bar + Bar;';
var
  mCurrent: TAtlasCarets;
begin
  Assert.AreEqual(Ord(TAtlasOccurrence.WordSelected), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([At(0, 8)]), False, False, mCurrent)));
  Assert.AreEqual('0:7>0:10', Show(mCurrent));
  // Direkt hinter dem Wort zählt es auch.
  Assert.AreEqual(Ord(TAtlasOccurrence.WordSelected), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([At(0, 3)]), False, False, mCurrent)));
  Assert.AreEqual('0:0>0:3', Show(mCurrent));
  // Kein Wort am Caret.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText), Carets([At(0, 5)]),
    False, False, mCurrent)));
  Assert.AreEqual('0:5', Show(mCurrent));
end;

procedure TAtlasMultiCursorTests.NextOccurrenceWrapsAndSkipsSelected;
const
  cText = 'Bar'#10'x := Bar;'#10'Bar';
var
  mCurrent, mNext: TAtlasCarets;
begin
  // Ab der letzten Zeile geht es am Dateiende von vorn weiter.
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([Range(2, 0, 2, 3)]), False, False, mCurrent)));
  Assert.AreEqual('2:0>2:3|0:0>0:3', Show(mCurrent));
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText), mCurrent, False,
    False, mNext)));
  Assert.AreEqual('2:0>2:3|0:0>0:3|1:5>1:8', Show(mNext));
  // Alle markiert: nichts mehr, die Marken bleiben.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText), mNext, False,
    False, mCurrent)));
  Assert.AreEqual(3, Integer(Length(mCurrent)));
  // Mehrzeilige Markierung sucht nicht.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([Range(0, 0, 1, 2)]), False, False, mCurrent)));
end;

procedure TAtlasMultiCursorTests.NextOccurrenceHonoursCaseAndWholeWord;
const
  cText = 'name := Name + Namen;';
var
  mCurrent: TAtlasCarets;
begin
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([Range(0, 0, 0, 4)]), False, False, mCurrent)));
  Assert.AreEqual('0:0>0:4|0:8>0:12', Show(mCurrent));
  // Groß-/Kleinschreibung beachten: „Name“ und „Namen“ passen nicht.
  Assert.AreEqual(Ord(TAtlasOccurrence.None), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([Range(0, 0, 0, 4)]), True, False, mCurrent)));
  Assert.AreEqual('0:0>0:4', Show(mCurrent));
  // Ganze Wörter: „Namen“ fällt weg, „Name“ bleibt.
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([Range(0, 8, 0, 12)]), False, True, mCurrent)));
  Assert.AreEqual('0:8>0:12|0:0>0:4', Show(mCurrent));
  Assert.AreEqual(Ord(TAtlasOccurrence.Added), Ord(TAtlasMultiCursor.NextOccurrence(Lines(cText),
    Carets([Range(0, 8, 0, 12)]), False, False, mCurrent)));
  Assert.AreEqual('0:8>0:12|0:15>0:19', Show(mCurrent));
end;

procedure TAtlasMultiCursorTests.SkipsLastOccurrence;
const
  cText = 'a b a b a';
var
  mCurrent: TAtlasCarets;
begin
  Assert.IsTrue(TAtlasMultiCursor.SkipOccurrence(Lines(cText), Carets([Range(0, 0, 0, 1), Range(0, 4, 0, 5)]), False,
    False, mCurrent));
  Assert.AreEqual('0:0>0:1|0:8>0:9', Show(mCurrent));
  Assert.IsFalse(TAtlasMultiCursor.SkipOccurrence(Lines(cText), Carets([Range(0, 0, 0, 1)]), False, False, mCurrent));
  Assert.AreEqual('0:0>0:1', Show(mCurrent));
end;

procedure TAtlasMultiCursorTests.BackspaceJoinsLines;
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab'#13#10'cd'#13#10'ef', Carets([At(1, 0), At(2, 1)]),
    TAtlasCaretEditKind.Backspace, '', mNewText, mAfter));
  Assert.AreEqual('abcd'#13#10'f', mNewText);
  Assert.AreEqual('0:2|1:0', Show(mAfter));
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab'#10'cd', Carets([At(1, 0)]), TAtlasCaretEditKind.Backspace, '', mNewText,
    mAfter));
  Assert.AreEqual('abcd', mNewText);
  Assert.AreEqual('0:2', Show(mAfter));
  // Am Dateianfang ändert sich nichts.
  Assert.IsFalse(TAtlasMultiCursor.Edit('ab', Carets([At(0, 0)]), TAtlasCaretEditKind.Backspace, '', mNewText,
    mAfter));
  Assert.AreEqual('ab', mNewText);
end;

procedure TAtlasMultiCursorTests.DeleteAtEndAndAcrossLineBreak;
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab'#13#10'cd', Carets([At(0, 2), At(1, 2)]), TAtlasCaretEditKind.Delete, '',
    mNewText, mAfter));
  Assert.AreEqual('abcd', mNewText);
  Assert.AreEqual('0:2|0:4', Show(mAfter));
  Assert.IsFalse(TAtlasMultiCursor.Edit('ab', Carets([At(0, 2)]), TAtlasCaretEditKind.Delete, '', mNewText, mAfter));
  Assert.IsTrue(TAtlasMultiCursor.Edit('abcd', Carets([At(0, 0), At(0, 2)]), TAtlasCaretEditKind.Delete, '',
    mNewText, mAfter));
  Assert.AreEqual('bd', mNewText);
  Assert.AreEqual('0:0|0:1', Show(mAfter));
end;

procedure TAtlasMultiCursorTests.NewLineKeepsIndent;
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('  ab'#13#10#9'cd', Carets([At(0, 3), At(1, 3)]),
    TAtlasCaretEditKind.NewLine, '', mNewText, mAfter));
  Assert.AreEqual('  a'#13#10'  b'#13#10#9'cd'#13#10#9, mNewText);
  Assert.AreEqual('1:2|3:1', Show(mAfter));
  // Marke im Einzug: höchstens bis zur Marke.
  Assert.IsTrue(TAtlasMultiCursor.Edit('    x', Carets([At(0, 2)]), TAtlasCaretEditKind.NewLine, '', mNewText, mAfter));
  Assert.AreEqual('  '#10'    x', mNewText);
  Assert.AreEqual('1:2', Show(mAfter));
end;

procedure TAtlasMultiCursorTests.InsertReplacesSelections;
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  Assert.IsTrue(TAtlasMultiCursor.Edit('one two'#10'three', Carets([Range(1, 5, 1, 0), At(0, 3), Range(0, 4, 0, 7)]),
    TAtlasCaretEditKind.Insert, 'X', mNewText, mAfter));
  Assert.AreEqual('oneX X'#10'X', mNewText);
  Assert.AreEqual('1:1|0:4|0:6', Show(mAfter));
  Assert.IsTrue(TAtlasMultiCursor.Edit('ab', Carets([Range(0, 0, 0, 1), At(0, 2)]), TAtlasCaretEditKind.Backspace,
    '', mNewText, mAfter));
  Assert.AreEqual('', mNewText);
  Assert.AreEqual('0:0', Show(mAfter));
  Assert.IsFalse(TAtlasMultiCursor.Edit('ab', Carets([At(0, 1)]), TAtlasCaretEditKind.Insert, '', mNewText, mAfter));
end;

procedure TAtlasMultiCursorTests.PastePartsRules;
var
  mParts: TArray<string>;
begin
  mParts := TAtlasMultiCursor.PasteParts('a'#13#10'b'#13#10, 2);
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual('a', mParts[0]);
  Assert.AreEqual('b', mParts[1]);
  mParts := TAtlasMultiCursor.PasteParts('a'#10'b'#10'c', 2);
  Assert.AreEqual(1, Integer(Length(mParts)));
  Assert.AreEqual('a'#10'b'#10'c', mParts[0]);
  // Ein leerer Teil in der Mitte zählt.
  mParts := TAtlasMultiCursor.PasteParts('a'#10#10'c', 3);
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual('', mParts[1]);
  mParts := TAtlasMultiCursor.PasteParts('', 1);
  Assert.AreEqual(1, Integer(Length(mParts)));
  mParts := nil;
end;

procedure TAtlasMultiCursorTests.CopiesSelectionsInTextOrder;
const
  cText = 'alpha beta'#13#10'gamma';
begin
  Assert.AreEqual('alpha'#13#10'beta'#13#10'gam', TAtlasMultiCursor.SelectedText(cText,
    Carets([Range(0, 6, 0, 10), Range(1, 3, 1, 0), Range(0, 0, 0, 5)]), #13#10));
  Assert.AreEqual('alpha'#10'beta'#10'gam', TAtlasMultiCursor.SelectedText(cText,
    Carets([Range(0, 6, 0, 10), Range(1, 3, 1, 0), Range(0, 0, 0, 5)]), #10));
  // Marken ohne Markierung zählen nicht; ohne Markierung ''.
  Assert.AreEqual('beta', TAtlasMultiCursor.SelectedText(cText, Carets([At(1, 1), Range(0, 6, 0, 10)]), #10));
  Assert.AreEqual('', TAtlasMultiCursor.SelectedText(cText, Carets([At(1, 1), At(0, 1)]), #10));
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
  cOld = 'kfNa := 1;'#13#10'kfNa := 2;'#13#10'kfNa := 3;';
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  // Getippt wurde „Na“ an drei Marken; die IDE übernimmt „Name“ an der Hauptmarke.
  Assert.IsTrue(TAtlasMultiCursor.Mirror(cOld, 'kfNa := 1;'#13#10'kfName := 2;'#13#10'kfNa := 3;',
    Carets([At(1, 4), At(0, 4), At(2, 4)]), mNewText, mAfter));
  Assert.AreEqual('kfName := 1;'#13#10'kfName := 2;'#13#10'kfName := 3;', mNewText);
  Assert.AreEqual('1:6|0:6|2:6', Show(mAfter));
  // Ersetzt die IDE das Präfix (gelöscht und eingefügt), gilt das an jeder Marke.
  Assert.IsTrue(TAtlasMultiCursor.Mirror('Na'#10'Na', 'Na'#10'Nummer', Carets([At(1, 2), At(0, 2)]), mNewText,
    mAfter));
  Assert.AreEqual('Nummer'#10'Nummer', mNewText);
  Assert.AreEqual('1:6|0:6', Show(mAfter));
  // Marken mit Markierung bleiben unberührt und rücken nur mit.
  Assert.IsTrue(TAtlasMultiCursor.Mirror('ab'#10'cd', 'abX'#10'cd', Carets([At(0, 2), Range(1, 0, 1, 2)]), mNewText,
    mAfter));
  Assert.AreEqual('abX'#10'cd', mNewText);
  Assert.AreEqual('0:3|1:0>1:2', Show(mAfter));
end;

procedure TAtlasMultiCursorTests.MirrorIgnoresChangesElsewhere;
var
  mAfter: TAtlasCarets;
  mNewText: string;
begin
  Assert.IsFalse(TAtlasMultiCursor.Mirror('abc'#10'def', 'abc'#10'dXef', Carets([At(0, 1), At(1, 3)]), mNewText,
    mAfter));
  Assert.AreEqual('abc'#10'dXef', mNewText);
  // Gelöschter Zeilenumbruch: nicht spiegeln.
  Assert.IsFalse(TAtlasMultiCursor.Mirror('ab'#10'cd', 'abcd', Carets([At(0, 2), At(1, 1)]), mNewText, mAfter));
  // Hauptmarke mit Markierung oder keine Änderung.
  Assert.IsFalse(TAtlasMultiCursor.Mirror('ab', 'aXb', Carets([Range(0, 0, 0, 1)]), mNewText, mAfter));
  Assert.IsFalse(TAtlasMultiCursor.Mirror('ab', 'ab', Carets([At(0, 1)]), mNewText, mAfter));
end;

procedure TAtlasMultiCursorTests.SplitsLines;
var
  mParts: TArray<string>;
begin
  mParts := TAtlasMultiCursor.Lines('a'#13#10'b'#10#10'c'#13#10);
  Assert.AreEqual(5, Integer(Length(mParts)));
  Assert.AreEqual('a', mParts[0]);
  Assert.AreEqual('b', mParts[1]);
  Assert.AreEqual('', mParts[2]);
  Assert.AreEqual('c', mParts[3]);
  Assert.AreEqual('', mParts[4]);
  Assert.AreEqual(1, Integer(Length(TAtlasMultiCursor.Lines(''))));
  Assert.AreEqual(#13#10, TAtlasMultiCursor.LineBreakOf('a'#10'b'#13#10));
  Assert.AreEqual(#10, TAtlasMultiCursor.LineBreakOf('a'#10'b'));
  mParts := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMultiCursorTests);

end.
