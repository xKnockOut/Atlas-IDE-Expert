unit Atlas.Core.Editor.MultiCursorSession.Tests;

// Tests für den Ablauf mehrerer Einfügemarken (TAtlasMultiCursorSession)
// gegen einen gefälschten Editorpuffer (TAtlasEditSurfaceFake): Strg+D
// (Wort, weitere Vorkommen), Tippen an allen Marken als ein
// Rückgängig-Schritt, Rückgängig der IDE bringt die Marken zurück, Änderung
// der IDE an der Hauptmarke (Mirror) und anderswo (verschieben), Datei
// gewechselt, Kopieren, Einfügen je Marke, Umschließen, Bewegen, Klick,
// Zeilenenden, schreibgeschützt, Hauptmarke nachziehen.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Core.Editor.MultiCursor,
  Atlas.Core.Editor.EditSurface,
  Atlas.Core.Editor.MultiCursorSession,
  Atlas.Tests.EditSurfaceFake;

type
  [TestFixture]
  TAtlasMultiCursorSessionTests = class
  private
    FFake: TAtlasEditSurfaceFake;
    FSurface: IAtlasEditSurface;
    FSession: TAtlasMultiCursorSession;
    FRefreshes: Integer;
    FFinishes: Integer;
    /// <summary>Drei Marken auf den x des Beispiels, je mit Markierung (Strg+D dreimal).</summary>
    procedure SelectAllX;
    /// <summary>Marken am Anfang der Zeilen AFirst und AFirst + 1.</summary>
    procedure TwoCarets(AFirst: Integer);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NextSelectsWordThenAddsOccurrences;
    [Test]
    procedure TypingWritesAllCaretsAsOneStep;
    [Test]
    procedure UndoOfOwnStepBringsCaretsBack;
    [Test]
    procedure IdeChangeAtMainCaretIsMirrored;
    [Test]
    procedure ChangeElsewhereShiftsCarets;
    [Test]
    procedure OtherFileEndsCarets;
    [Test]
    procedure CopiesSelectionsLineByLine;
    [Test]
    procedure PastesOneLinePerCaret;
    [Test]
    procedure WrapsAllSelections;
    [Test]
    procedure MovesAllCarets;
    [Test]
    procedure ToggleAddsAndRemovesCaret;
    [Test]
    procedure LineEndsNeedSelection;
    [Test]
    procedure ReadOnlyBufferIsLeftAlone;
    [Test]
    procedure SyncMainFollowsIdeCursor;
    [Test]
    procedure FinishReportsOnce;
  end;

implementation

const
  cFile = 'C:\Projekt\Unit1.pas';
  cText = 'a := x;'#10'b := x;'#10'c := x;';

{ TAtlasMultiCursorSessionTests }

procedure TAtlasMultiCursorSessionTests.Setup;
begin
  FRefreshes := 0;
  FFinishes := 0;
  FSession := TAtlasMultiCursorSession.Create(
    procedure
    begin
      Inc(FFinishes);
    end,
    procedure
    begin
      Inc(FRefreshes);
    end);
  FFake := TAtlasEditSurfaceFake.Create(cFile, cText);
  FSurface := FFake;
end;

procedure TAtlasMultiCursorSessionTests.TearDown;
begin
  FreeAndNil(FSession);
  FFake := nil;
  FSurface := nil;
end;

procedure TAtlasMultiCursorSessionTests.SelectAllX;
begin
  FFake.Caret(0, 5);
  Assert.IsTrue(FSession.Next(FSurface));
  Assert.IsTrue(FSession.Next(FSurface));
  Assert.IsTrue(FSession.Next(FSurface));
  Assert.AreEqual(3, FSession.Count);
end;

procedure TAtlasMultiCursorSessionTests.TwoCarets(AFirst: Integer);
begin
  FFake.Caret(AFirst, 0);
  Assert.IsTrue(FSession.Vertical(FSurface, False));
  Assert.AreEqual(2, FSession.Count);
end;

procedure TAtlasMultiCursorSessionTests.NextSelectsWordThenAddsOccurrences;
var
  mAnchorLine, mAnchorCharacter, mLine, mCharacter: Integer;
begin
  FFake.Caret(0, 5);
  Assert.IsTrue(FSession.Next(FSurface), 'Wort am Cursor');
  Assert.IsFalse(FSession.Active, 'noch eine Marke');
  FFake.ReadSelection(mAnchorLine, mAnchorCharacter, mLine, mCharacter);
  Assert.AreEqual(5, mAnchorCharacter);
  Assert.AreEqual(6, mCharacter);
  Assert.AreEqual(1, FFake.Paints);
  Assert.IsTrue(FSession.Next(FSurface), 'nächstes Vorkommen');
  Assert.IsTrue(FSession.Active);
  Assert.AreEqual(2, FSession.Count);
  Assert.AreEqual(1, FSession.Carets[1].Line);
  Assert.AreEqual(1, FFake.Revealed, 'neue Marke sichtbar');
  Assert.AreEqual(1, FRefreshes);
  FFake.Caret(0, 2);
  FSession.Finish;
  Assert.IsFalse(FSession.Next(FSurface), 'kein Wort: Taste an die IDE');
end;

procedure TAtlasMultiCursorSessionTests.TypingWritesAllCaretsAsOneStep;
begin
  SelectAllX;
  FSession.DoEdit(FSurface, TAtlasCaretEditKind.Insert, 'yz');
  Assert.AreEqual('a := yz;'#10'b := yz;'#10'c := yz;', FFake.Text);
  Assert.AreEqual(1, FFake.Writes);
  Assert.AreEqual(1, FFake.UndoDepth, 'ein Schritt für alle Marken');
  Assert.AreEqual(3, FSession.Count);
  Assert.AreEqual(7, FSession.Carets[2].Character);
  Assert.AreEqual('b := yz;', FSession.LineText(1));
end;

procedure TAtlasMultiCursorSessionTests.UndoOfOwnStepBringsCaretsBack;
begin
  SelectAllX;
  FSession.DoEdit(FSurface, TAtlasCaretEditKind.Insert, 'y');
  Assert.IsTrue(FFake.Undo);
  FSession.BufferChanged;
  Assert.AreEqual(cText, FFake.Text);
  Assert.AreEqual(3, FSession.Count);
  Assert.IsTrue(FSession.Carets[2].HasSelection, 'Marken samt Markierung von vorher');
  Assert.AreEqual(1, FFake.Writes, 'Rückgängig schreibt nichts');
  Assert.IsTrue(FFake.Redo);
  FSession.BufferChanged;
  Assert.IsFalse(FSession.Carets[2].HasSelection, 'Wiederholen: Marken von nachher');
end;

procedure TAtlasMultiCursorSessionTests.IdeChangeAtMainCaretIsMirrored;
begin
  TwoCarets(0);
  // Die IDE schreibt selbst an der Hauptmarke (Vorschlag übernommen, Tab).
  FFake.TypeText('Za := x;'#10'b := x;'#10'c := x;', 0, 1);
  FSession.BufferChanged;
  Assert.AreEqual('Za := x;'#10'Zb := x;'#10'c := x;', FFake.Text);
  Assert.AreEqual(2, FFake.UndoDepth, 'Änderung der IDE und eigener Schritt');
  Assert.AreEqual(1, FSession.Carets[1].Character);
end;

procedure TAtlasMultiCursorSessionTests.ChangeElsewhereShiftsCarets;
const
  cLonger = 'a := x;'#10'b := x;'#10'c := x;'#10'd := x;';
begin
  TwoCarets(0);
  FFake.TypeText(cLonger, 0, 0);
  FSession.BufferChanged;
  Assert.AreEqual(cLonger, FFake.Text, 'nichts geschrieben');
  Assert.AreEqual(2, FSession.Count);
  Assert.AreEqual(1, FSession.Carets[1].Line);
  Assert.AreEqual('d := x;', FSession.LineText(3));
end;

procedure TAtlasMultiCursorSessionTests.OtherFileEndsCarets;
var
  mOther: IAtlasEditSurface;
begin
  TwoCarets(0);
  mOther := TAtlasEditSurfaceFake.Create('C:\Projekt\Unit2.pas', 'x');
  FSession.DoEdit(mOther, TAtlasCaretEditKind.Insert, 'y');
  Assert.AreEqual(1, FFinishes);
  Assert.AreEqual('yx', mOther.Text, 'die Taste gilt der neuen Datei, mit einer Marke');
  Assert.AreEqual(cText, FFake.Text);
  Assert.IsFalse(FSession.Active);
end;

procedure TAtlasMultiCursorSessionTests.CopiesSelectionsLineByLine;
var
  mText: string;
begin
  TwoCarets(0);
  Assert.IsFalse(FSession.Selected(FSurface, mText), 'ohne Markierung bleibt Kopieren der IDE');
  FSession.Finish;
  SelectAllX;
  Assert.IsTrue(FSession.Selected(FSurface, mText));
  Assert.AreEqual('x'#10'x'#10'x', mText);
end;

procedure TAtlasMultiCursorSessionTests.PastesOneLinePerCaret;
begin
  SelectAllX;
  FSession.DoPaste(FSurface, '1'#10'2'#10'3');
  Assert.AreEqual('a := 1;'#10'b := 2;'#10'c := 3;', FFake.Text);
  Assert.AreEqual(1, FFake.UndoDepth);
end;

procedure TAtlasMultiCursorSessionTests.WrapsAllSelections;
begin
  SelectAllX;
  Assert.IsFalse(FSession.DoWrap(FSurface, '(', '['), 'Zeichen nicht eingeschaltet');
  Assert.IsTrue(FSession.DoWrap(FSurface, '(', '(['));
  Assert.AreEqual('a := (x);'#10'b := (x);'#10'c := (x);', FFake.Text);
  Assert.AreEqual(1, FFake.UndoDepth);
end;

procedure TAtlasMultiCursorSessionTests.MovesAllCarets;
var
  mLine, mCharacter: Integer;
begin
  TwoCarets(0);
  FSession.DoMove(FSurface, TAtlasCaretMove.LineEnd, False);
  Assert.AreEqual(7, FSession.Carets[0].Character);
  Assert.AreEqual(7, FSession.Carets[1].Character);
  FFake.ReadCaret(mLine, mCharacter);
  Assert.AreEqual(7, mCharacter, 'Hauptmarke im Puffer gesetzt');
  Assert.AreEqual(0, FFake.Writes);
end;

procedure TAtlasMultiCursorSessionTests.ToggleAddsAndRemovesCaret;
begin
  FFake.Caret(0, 0);
  Assert.IsTrue(FSession.Toggle(FSurface, cFile, 2, 3));
  Assert.AreEqual(2, FSession.Count);
  Assert.AreEqual(3, FSession.Carets[1].Character);
  Assert.IsTrue(FSession.Toggle(FSurface, cFile, 2, 3));
  Assert.AreEqual(1, FSession.Count, 'zweiter Klick entfernt die Marke');
  Assert.IsFalse(FSession.Toggle(FSurface, 'C:\Projekt\Unit2.pas', 1, 0), 'Klick in andere Datei');
end;

procedure TAtlasMultiCursorSessionTests.LineEndsNeedSelection;
begin
  FFake.Caret(2, 3);
  Assert.IsFalse(FSession.LineEnds(FSurface));
  FFake.SelectFrom(0, 0);
  Assert.IsTrue(FSession.LineEnds(FSurface));
  Assert.AreEqual(3, FSession.Count);
  Assert.AreEqual(7, FSession.Carets[1].Character);
end;

procedure TAtlasMultiCursorSessionTests.ReadOnlyBufferIsLeftAlone;
begin
  FFake.ReadOnly := True;
  FFake.Caret(0, 5);
  Assert.IsFalse(FSession.Next(FSurface));
  FSession.DoEdit(FSurface, TAtlasCaretEditKind.Insert, 'y');
  Assert.AreEqual(cText, FFake.Text);
end;

procedure TAtlasMultiCursorSessionTests.SyncMainFollowsIdeCursor;
begin
  TwoCarets(0);
  // Die IDE bewegt den Cursor ohne Atlas (Suchen, Bild ab).
  FFake.Caret(2, 4);
  FSession.SyncMain;
  Assert.AreEqual(2, FSession.Carets[0].Line);
  Assert.AreEqual(4, FSession.Carets[0].Character);
end;

procedure TAtlasMultiCursorSessionTests.FinishReportsOnce;
begin
  TwoCarets(0);
  FSession.Finish;
  FSession.Finish;
  Assert.AreEqual(1, FFinishes);
  Assert.AreEqual('', FSession.FileName);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMultiCursorSessionTests);

end.
