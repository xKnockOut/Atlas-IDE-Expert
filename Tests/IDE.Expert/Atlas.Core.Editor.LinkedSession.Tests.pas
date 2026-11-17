unit Atlas.Core.Editor.LinkedSession.Tests;

// Tests für den Ablauf einer Sitzung „Bezeichner live mitziehen“
// (TAtlasLinkedSession) gegen einen gefälschten Editorpuffer
// (TAtlasEditSurfaceFake): Beginn nur mit passender Antwort, eine Sitzung als
// ein Rückgängig-Schritt, Ende an den Rändern des Namens und bei Zeichen, die
// kein Bezeichner sind, Änderung der IDE am Namen (nachziehen) und anderswo
// (enden), Konflikte samt Esc, Cursor verlässt den Namen, Puffer anders als
// gerechnet, Zurücknehmen verweigert, Markierung.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Core.Editor.LinkedEditing,
  Atlas.Core.Editor.EditSurface,
  Atlas.Core.Editor.LinkedSession,
  Atlas.Tests.EditSurfaceFake;

type
  [TestFixture]
  TAtlasLinkedSessionTests = class
  private
    FFake: TAtlasEditSurfaceFake;
    FSurface: IAtlasEditSurface;
    FSession: TAtlasLinkedSession;
    FRefreshes: Integer;
    FFinishes: Integer;
    /// <summary>Puffer mit AText und Cursor auf ALine/ACharacter.</summary>
    procedure Open(const AText: string; ALine, ACharacter: Integer);
    /// <summary>Die drei Vorkommen von Count im Beispiel.</summary>
    function CountRanges: TAtlasLinkedRanges;
    /// <summary>Sitzung im Beispiel mit Cursor auf ALine/ACharacter beginnen.</summary>
    function StartCount(ALine, ACharacter: Integer): Boolean;
    function Key(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
    /// <summary>Beispiel mit AName statt Count.</summary>
    function Renamed(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StartsOnlyWhenAnswerFitsBuffer;
    [Test]
    procedure TypingRenamesAllOccurrences;
    [Test]
    procedure SessionIsOneUndoStep;
    [Test]
    procedure KeysAtEdgesOfNameEndSession;
    [Test]
    procedure NonNameCharEndsSession;
    [Test]
    procedure FollowsIdeChangeOfName;
    [Test]
    procedure ChangeElsewhereEndsSession;
    [Test]
    procedure ReservedWordIsConflictAndEscRestores;
    [Test]
    procedure VisibleNameIsConflict;
    [Test]
    procedure RestoreAfterIdeChangeWritesOriginal;
    [Test]
    procedure CaretLeavingNameEndsSession;
    [Test]
    procedure CheckFollowsPendingChange;
    [Test]
    procedure UnexpectedBufferEndsSession;
    [Test]
    procedure RefusedUndoWritesOwnStep;
    [Test]
    procedure SelectionGivesKeyToIde;
    [Test]
    procedure EditsAreSortedAndUnique;
    [Test]
    procedure FinishReportsOnce;
  end;

implementation

const
  cFile = 'C:\Projekt\Unit1.pas';
  cText = 'procedure P;'#10'var'#10'  Count: Integer;'#10'begin'#10'  Count := Count + 1;'#10'end;';

{ TAtlasLinkedSessionTests }

procedure TAtlasLinkedSessionTests.Setup;
begin
  FRefreshes := 0;
  FFinishes := 0;
  FSession := TAtlasLinkedSession.Create(
    procedure
    begin
      Inc(FRefreshes);
    end,
    procedure
    begin
      Inc(FFinishes);
    end);
  Open(cText, 4, 4);
end;

procedure TAtlasLinkedSessionTests.TearDown;
begin
  FreeAndNil(FSession);
  if FFake <> nil then
  begin
    FFake.OnWrite := nil;
  end;
  FFake := nil;
  FSurface := nil;
end;

procedure TAtlasLinkedSessionTests.Open(const AText: string; ALine, ACharacter: Integer);
begin
  FSurface := nil;
  FFake := TAtlasEditSurfaceFake.Create(cFile, AText);
  FSurface := FFake;
  FFake.Caret(ALine, ACharacter);
end;

function TAtlasLinkedSessionTests.CountRanges: TAtlasLinkedRanges;
begin
  Result := nil;
  SetLength(Result, 3);
  Result[0] := TAtlasLinkedRange.Create(2, 2, 5);
  Result[1] := TAtlasLinkedRange.Create(4, 2, 5);
  Result[2] := TAtlasLinkedRange.Create(4, 11, 5);
end;

function TAtlasLinkedSessionTests.StartCount(ALine, ACharacter: Integer): Boolean;
begin
  FFake.Caret(ALine, ACharacter);
  Result := FSession.Start(FSurface, cFile, cText, CountRanges, nil);
end;

function TAtlasLinkedSessionTests.Key(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
begin
  Result := FSession.Key(FSurface, AKind, AInsert);
end;

function TAtlasLinkedSessionTests.Renamed(const AName: string): string;
begin
  Result := StringReplace(cText, 'Count', AName, [rfReplaceAll]);
end;

procedure TAtlasLinkedSessionTests.StartsOnlyWhenAnswerFitsBuffer;
begin
  Assert.IsFalse(FSession.Start(FSurface, cFile, cText + ' ', CountRanges, nil), 'anderer Text');
  Assert.IsFalse(FSession.Start(FSurface, 'C:\Projekt\Unit2.pas', cText, CountRanges, nil), 'andere Datei');
  Assert.IsFalse(StartCount(3, 0), 'Cursor außerhalb');
  FFake.Caret(4, 4);
  FFake.SelectFrom(4, 2);
  Assert.IsFalse(FSession.Start(FSurface, cFile, cText, CountRanges, nil), 'Markierung');
  FFake.Caret(4, 4);
  FFake.ReadOnly := True;
  Assert.IsFalse(StartCount(4, 4), 'schreibgeschützt');
  FFake.ReadOnly := False;
  Assert.IsFalse(FSession.Active);
  Assert.IsTrue(StartCount(4, 4));
  Assert.IsTrue(FSession.Active);
  Assert.AreEqual(1, FSession.Primary);
  Assert.AreEqual('Count', FSession.Original);
  Assert.AreEqual(cFile, FSession.FileName);
  Assert.AreEqual(0, FFake.Writes, 'Beginn schreibt nichts');
end;

procedure TAtlasLinkedSessionTests.TypingRenamesAllOccurrences;
var
  mLine, mCharacter: Integer;
begin
  Assert.IsTrue(StartCount(4, 4));
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'X'));
  Assert.AreEqual(Renamed('CoXunt'), FFake.Text);
  FFake.ReadCaret(mLine, mCharacter);
  Assert.AreEqual(4, mLine);
  Assert.AreEqual(5, mCharacter);
  Assert.AreEqual(1, FRefreshes);
  Assert.AreEqual(1, FFake.Writes);
  Assert.AreEqual('CoXunt', FSession.PrimaryName);
end;

procedure TAtlasLinkedSessionTests.SessionIsOneUndoStep;
begin
  Assert.IsTrue(StartCount(4, 4));
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'X'));
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'Y'));
  Assert.IsTrue(Key(TAtlasLinkedKey.Backspace, ''));
  Assert.AreEqual(Renamed('CoXunt'), FFake.Text);
  Assert.AreEqual(1, FFake.UndoDepth, 'die ganze Sitzung ist ein Schritt');
  Assert.IsTrue(FFake.Undo);
  Assert.AreEqual(cText, FFake.Text);
end;

procedure TAtlasLinkedSessionTests.KeysAtEdgesOfNameEndSession;
begin
  Assert.IsTrue(StartCount(4, 2));
  Assert.IsFalse(Key(TAtlasLinkedKey.Backspace, ''), 'Rücktaste am Anfang');
  Assert.IsFalse(FSession.Active);
  Assert.AreEqual(1, FFinishes);
  Assert.IsTrue(StartCount(4, 7));
  Assert.IsFalse(Key(TAtlasLinkedKey.Delete, ''), 'Entf am Ende');
  Assert.IsFalse(FSession.Active);
  Assert.AreEqual(2, FFinishes);
  Assert.AreEqual(cText, FFake.Text);
  Assert.AreEqual(0, FFake.Writes);
end;

procedure TAtlasLinkedSessionTests.NonNameCharEndsSession;
begin
  Assert.IsTrue(StartCount(4, 4));
  Assert.IsFalse(Key(TAtlasLinkedKey.Insert, '.'));
  Assert.IsFalse(FSession.Active);
  Assert.AreEqual(cText, FFake.Text);
end;

procedure TAtlasLinkedSessionTests.FollowsIdeChangeOfName;
begin
  Assert.IsTrue(StartCount(4, 4));
  // Die IDE fügt selbst ein (Zwischenablage): nur das bearbeitete Vorkommen ändert sich.
  FFake.TypeText(StringReplace(cText, '  Count := ', '  Total := ', []), 4, 7);
  FSession.BufferChanged;
  Assert.IsTrue(FSession.Active);
  Assert.AreEqual(Renamed('Total'), FFake.Text);
  Assert.AreEqual(2, FFake.UndoDepth, 'Änderung der IDE und Nachziehen');
  Assert.AreEqual(1, FRefreshes);
  // Ab hier ein Schritt je Taste: der Schritt der IDE wird nicht zurückgenommen.
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'X'));
  Assert.AreEqual(Renamed('TotalX'), FFake.Text);
  Assert.AreEqual(3, FFake.UndoDepth);
end;

procedure TAtlasLinkedSessionTests.ChangeElsewhereEndsSession;
begin
  Assert.IsTrue(StartCount(4, 4));
  FFake.TypeText(StringReplace(cText, 'procedure P;', 'procedure Q;', []), 0, 11);
  FSession.BufferChanged;
  Assert.IsFalse(FSession.Active);
  Assert.AreEqual(1, FFinishes);
  Assert.AreEqual(0, FFake.Writes);
end;

procedure TAtlasLinkedSessionTests.ReservedWordIsConflictAndEscRestores;
const
  cShort = 'begin'#10'  o := o;'#10'end;';
var
  mRanges: TAtlasLinkedRanges;
  mLine, mCharacter: Integer;
begin
  Open(cShort, 1, 3);
  mRanges := nil;
  SetLength(mRanges, 2);
  mRanges[0] := TAtlasLinkedRange.Create(1, 2, 1);
  mRanges[1] := TAtlasLinkedRange.Create(1, 7, 1);
  Assert.IsTrue(FSession.Start(FSurface, cFile, cShort, mRanges, nil));
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'f'));
  Assert.AreEqual('begin'#10'  of := of;'#10'end;', FFake.Text);
  Assert.AreEqual(Ord(TAtlasLinkedProblem.Reserved), Ord(FSession.Problem));
  FSession.Restore;
  Assert.AreEqual(cShort, FFake.Text);
  FFake.ReadCaret(mLine, mCharacter);
  Assert.AreEqual(1, mLine);
  Assert.AreEqual(3, mCharacter, 'Cursor hinter dem alten Namen');
  Assert.AreEqual(0, FFake.UndoDepth, 'der eigene Schritt ist zurückgenommen');
end;

procedure TAtlasLinkedSessionTests.VisibleNameIsConflict;
var
  mConflicts: TAtlasLinkedConflicts;
begin
  mConflicts := nil;
  SetLength(mConflicts, 1);
  mConflicts[0].Name := 'CountX';
  mConflicts[0].Detail := 'Feld CountX';
  FFake.Caret(4, 7);
  Assert.IsTrue(FSession.Start(FSurface, cFile, cText, CountRanges, mConflicts));
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'X'));
  Assert.AreEqual(Ord(TAtlasLinkedProblem.Visible), Ord(FSession.Problem));
  Assert.AreEqual('Feld CountX', FSession.Detail);
  Assert.IsTrue(Key(TAtlasLinkedKey.Backspace, ''));
  Assert.AreEqual(Ord(TAtlasLinkedProblem.None), Ord(FSession.Problem), 'alter Name ist nie ein Konflikt');
end;

procedure TAtlasLinkedSessionTests.RestoreAfterIdeChangeWritesOriginal;
var
  mLine, mCharacter: Integer;
begin
  Assert.IsTrue(StartCount(4, 4));
  FFake.TypeText(StringReplace(cText, '  Count := ', '  Total := ', []), 4, 7);
  FSession.BufferChanged;
  Assert.AreEqual(Renamed('Total'), FFake.Text);
  FSession.Restore;
  Assert.AreEqual(cText, FFake.Text, 'alter Name in allen Vorkommen');
  FFake.ReadCaret(mLine, mCharacter);
  Assert.AreEqual(4, mLine);
  Assert.AreEqual(7, mCharacter);
end;

procedure TAtlasLinkedSessionTests.CaretLeavingNameEndsSession;
begin
  Assert.IsTrue(StartCount(4, 4));
  FSession.Check(FSurface);
  Assert.IsTrue(FSession.Active, 'Cursor im Namen');
  FFake.Caret(4, 10);
  FSession.Check(FSurface);
  Assert.IsFalse(FSession.Active);
  Assert.AreEqual(1, FFinishes);
end;

procedure TAtlasLinkedSessionTests.CheckFollowsPendingChange;
begin
  Assert.IsTrue(StartCount(4, 4));
  // Die Meldung der Änderung steht noch aus: der Takt zieht sie nach.
  FFake.TypeText(StringReplace(cText, '  Count := ', '  Sum := ', []), 4, 5);
  FSession.Check(FSurface);
  Assert.IsTrue(FSession.Active);
  Assert.AreEqual(Renamed('Sum'), FFake.Text);
end;

procedure TAtlasLinkedSessionTests.UnexpectedBufferEndsSession;
begin
  Assert.IsTrue(StartCount(4, 4));
  FFake.OnWrite :=
    procedure
    begin
      FFake.Overwrite(FFake.Text + ' ');
    end;
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'X'), 'die Taste ist verbraucht');
  Assert.IsFalse(FSession.Active);
  Assert.AreEqual(0, FRefreshes);
  Assert.AreEqual(1, FFake.Writes, 'nichts weiter geschrieben');
end;

procedure TAtlasLinkedSessionTests.RefusedUndoWritesOwnStep;
begin
  Assert.IsTrue(StartCount(4, 4));
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'X'));
  // Nimmt der Puffer den eigenen Schritt nicht zurück, steht noch der letzte Stand: ab ihm weiterschreiben.
  FFake.UndoFails := True;
  Assert.IsTrue(Key(TAtlasLinkedKey.Insert, 'Y'));
  Assert.IsTrue(FSession.Active);
  Assert.AreEqual(Renamed('CoXYunt'), FFake.Text);
  Assert.AreEqual(2, FFake.UndoDepth, 'zwei Schritte statt einem');
end;

procedure TAtlasLinkedSessionTests.SelectionGivesKeyToIde;
begin
  Assert.IsTrue(StartCount(4, 4));
  FFake.SelectFrom(4, 2);
  Assert.IsFalse(Key(TAtlasLinkedKey.Insert, 'X'));
  Assert.IsFalse(FSession.Active);
  Assert.AreEqual(cText, FFake.Text);
end;

procedure TAtlasLinkedSessionTests.EditsAreSortedAndUnique;
var
  mRanges: TAtlasLinkedRanges;
  mEdits: TAtlasTextEdits;
begin
  mRanges := nil;
  SetLength(mRanges, 4);
  mRanges[0] := TAtlasLinkedRange.Create(4, 11, 5);
  mRanges[1] := TAtlasLinkedRange.Create(2, 2, 5);
  mRanges[2] := TAtlasLinkedRange.Create(4, 2, 5);
  mRanges[3] := TAtlasLinkedRange.Create(2, 2, 5);
  mEdits := TAtlasLinkedSession.Edits(cText, mRanges, 'N', 2);
  Assert.AreEqual(2, Integer(Length(mEdits)), 'doppelter Anfang einmal, übersprungener fehlt');
  Assert.AreEqual(Pos('Count', cText) - 1, mEdits[0].Start);
  Assert.AreEqual(5, mEdits[0].Count);
  Assert.AreEqual('N', mEdits[0].Insert);
  Assert.AreEqual(Pos('Count + 1', cText) - 1, mEdits[1].Start);
end;

procedure TAtlasLinkedSessionTests.FinishReportsOnce;
begin
  Assert.IsTrue(StartCount(4, 4));
  FSession.Finish;
  FSession.Finish;
  Assert.AreEqual(1, FFinishes);
  Assert.AreEqual('', FSession.FileName);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkedSessionTests);

end.
