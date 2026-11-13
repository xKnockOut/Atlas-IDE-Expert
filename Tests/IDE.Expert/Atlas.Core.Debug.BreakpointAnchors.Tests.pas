unit Atlas.Core.Debug.BreakpointAnchors.Tests;

// Tests für Haltepunkte, die mit dem Code wandern (#841), ohne IDE:
// eingefügte Zeilen, umbenannte Routine, doppelte Zeilentexte, entfernte
// Zeile, Bearbeitung in der Zeile, Speichern und Laden.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.BreakpointAnchors;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointAnchorsTests = class
  private
    function Item(const AText: string; ALine: Integer): TAtlasAnchoredBreakpoint;
  public
    [Test]
    procedure UnchangedTextKeeps;
    /// <summary>Akzeptanzkriterium: zehn Zeilen über der Routine eingefügt.</summary>
    [Test]
    procedure InsertedLinesMove;
    [Test]
    procedure RenamedRoutineMoves;
    [Test]
    procedure DuplicateTextsStayInRoutine;
    /// <summary>Akzeptanzkriterium: Zeile entfernt, verwaist mit Vorschlag.</summary>
    [Test]
    procedure RemovedLineIsOrphan;
    [Test]
    procedure EditedLineKeeps;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure ForeignFormatIsRejected;
    [Test]
    procedure ExternalChanges;
    [Test]
    procedure MovesDoNotCollide;
    /// <summary>Akzeptanzkriterium: „Rückgängig“ stellt die alten Positionen her.</summary>
    [Test]
    procedure ReversedRestoresOldLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.MethodAnchor;

const
  cSource =
    'unit Kunden;' + #10 +
    'interface' + #10 +
    'implementation' + #10 +
    '' + #10 +
    'procedure Speichere;' + #10 +
    'begin' + #10 +
    '  Pruefe;' + #10 +
    '  Schreibe;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'procedure Lade;' + #10 +
    'begin' + #10 +
    '  Lies;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'end.' + #10;
  // Zeilen (ab 0) in cSource.
  cWriteLine = 7;
  cReadLine = 12;
  cInserted = 10;

function TAtlasBreakpointAnchorsTests.Item(const AText: string; ALine: Integer): TAtlasAnchoredBreakpoint;
begin
  Result := TAtlasAnchoredBreakpoint.Create('C:\Src\Kunden.pas', ALine, TAtlasMethodAnchors.Capture(AText, ALine));
end;

function Blank(ACount: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to ACount do
  begin
    Result := Result + '// eingefügt' + #10;
  end;
end;

procedure TAtlasBreakpointAnchorsTests.UnchangedTextKeeps;
var
  mResult: TAtlasAnchorResult;
begin
  mResult := TAtlasBreakpointAnchors.Follow(cSource, Item(cSource, cWriteLine));
  Assert.AreEqual(Ord(TAtlasAnchorStep.Keep), Ord(mResult.Step));
  Assert.AreEqual(cWriteLine, mResult.Line);
end;

procedure TAtlasBreakpointAnchorsTests.InsertedLinesMove;
var
  mText: string;
  mResult: TAtlasAnchorResult;
begin
  mText := StringReplace(cSource, 'implementation' + #10, 'implementation' + #10 + Blank(cInserted), []);
  mResult := TAtlasBreakpointAnchors.Follow(mText, Item(cSource, cWriteLine));
  Assert.AreEqual(Ord(TAtlasAnchorStep.Move), Ord(mResult.Step));
  Assert.AreEqual(cWriteLine + cInserted, mResult.Line);
end;

procedure TAtlasBreakpointAnchorsTests.RenamedRoutineMoves;
var
  mText: string;
  mResult: TAtlasAnchorResult;
begin
  mText := StringReplace(cSource, 'procedure Speichere;', 'procedure Sichere;', []);
  mText := StringReplace(mText, 'implementation' + #10, 'implementation' + #10 + Blank(2), []);
  mResult := TAtlasBreakpointAnchors.Follow(mText, Item(cSource, cWriteLine));
  Assert.AreEqual(Ord(TAtlasAnchorStep.Move), Ord(mResult.Step));
  Assert.AreEqual(cWriteLine + 2, mResult.Line);
end;

procedure TAtlasBreakpointAnchorsTests.DuplicateTextsStayInRoutine;
var
  mText: string;
  mResult: TAtlasAnchorResult;
begin
  // Eine zweite Routine mit derselben Zeile „Lies;“ davor: Der Haltepunkt bleibt in Lade.
  mText := StringReplace(cSource, 'procedure Lade;',
    'procedure Vorher;' + #10 + 'begin' + #10 + '  Lies;' + #10 + 'end;' + #10 + #10 + 'procedure Lade;', []);
  mResult := TAtlasBreakpointAnchors.Follow(mText, Item(cSource, cReadLine));
  Assert.AreEqual(Ord(TAtlasAnchorStep.Move), Ord(mResult.Step));
  Assert.AreEqual(cReadLine + 5, mResult.Line);
end;

procedure TAtlasBreakpointAnchorsTests.RemovedLineIsOrphan;
var
  mText: string;
  mResult: TAtlasAnchorResult;
begin
  mText := StringReplace(cSource, '  Schreibe;' + #10, '', []);
  mText := StringReplace(mText, 'implementation' + #10, 'implementation' + #10 + Blank(3), []);
  mResult := TAtlasBreakpointAnchors.Follow(mText, Item(cSource, cWriteLine));
  Assert.AreEqual(Ord(TAtlasAnchorStep.Orphan), Ord(mResult.Step));
  // Vorschlag: gleicher Abstand im Rumpf von Speichere (jetzt die Zeile „end;“).
  Assert.AreEqual(cWriteLine + 3, mResult.Line);
end;

procedure TAtlasBreakpointAnchorsTests.EditedLineKeeps;
var
  mText: string;
  mResult: TAtlasAnchorResult;
begin
  mText := StringReplace(cSource, '  Schreibe;', '  Schreibe(True);', []);
  mResult := TAtlasBreakpointAnchors.Follow(mText, Item(cSource, cWriteLine));
  Assert.AreEqual(Ord(TAtlasAnchorStep.Keep), Ord(mResult.Step));
  Assert.AreEqual(cWriteLine, mResult.Line);
end;

procedure TAtlasBreakpointAnchorsTests.JsonRoundTrip;
var
  mItems: TAtlasAnchoredBreakpoints;
begin
  Assert.IsTrue(TAtlasBreakpointAnchors.Parse(TAtlasBreakpointAnchors.ToJson([Item(cSource, cWriteLine),
    Item(cSource, cReadLine)]), mItems));
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('C:\Src\Kunden.pas', mItems[0].FileName);
  Assert.AreEqual(cWriteLine, mItems[0].Line);
  Assert.AreEqual('Speichere', mItems[0].Anchor.Method);
  Assert.IsTrue(mItems[1].Anchor.SameAs(Item(cSource, cReadLine).Anchor));
  Assert.AreEqual(TAtlasBreakpointAnchors.Key('C:\SRC\kunden.pas', 3),
    TAtlasBreakpointAnchors.Key('c:\src\Kunden.pas', 3));
end;

procedure TAtlasBreakpointAnchorsTests.ForeignFormatIsRejected;
var
  mItems: TAtlasAnchoredBreakpoints;
begin
  Assert.IsFalse(TAtlasBreakpointAnchors.Parse('{"format": 99, "breakpoints": []}', mItems));
  Assert.IsFalse(TAtlasBreakpointAnchors.Parse('kein JSON', mItems));
  Assert.AreEqual(0, Integer(Length(mItems)));
end;

procedure TAtlasBreakpointAnchorsTests.ExternalChanges;
begin
  Assert.IsTrue(TAtlasBreakpointAnchors.IsExternal(False, False, 0, 10));
  Assert.IsTrue(TAtlasBreakpointAnchors.IsExternal(True, True, 10, 10));
  Assert.IsTrue(TAtlasBreakpointAnchors.IsExternal(True, False, 10, 10 + TAtlasBreakpointAnchors.cBulkLines));
  Assert.IsTrue(TAtlasBreakpointAnchors.IsExternal(True, False, 20, 20 - TAtlasBreakpointAnchors.cBulkLines));
  Assert.IsFalse(TAtlasBreakpointAnchors.IsExternal(True, False, 10, 11));
end;

procedure TAtlasBreakpointAnchorsTests.MovesDoNotCollide;
var
  mMoves: TAtlasAnchorMoves;
begin
  // 7 -> 9 und 9 -> 11: erst 9 verschieben, sonst stünde 7 auf dem Platz von 9. Nach oben umgekehrt.
  mMoves := TAtlasBreakpointAnchors.Ordered([TAtlasAnchorMove.Create('a.pas', 7, 9),
    TAtlasAnchorMove.Create('a.pas', 9, 11), TAtlasAnchorMove.Create('a.pas', 20, 20),
    TAtlasAnchorMove.Create('a.pas', 30, 28), TAtlasAnchorMove.Create('a.pas', 32, 30)]);
  Assert.AreEqual(4, Integer(Length(mMoves)));
  Assert.AreEqual(9, mMoves[0].FromLine);
  Assert.AreEqual(7, mMoves[1].FromLine);
  Assert.AreEqual(30, mMoves[2].FromLine);
  Assert.AreEqual(32, mMoves[3].FromLine);
end;

procedure TAtlasBreakpointAnchorsTests.ReversedRestoresOldLines;
var
  mMoves: TAtlasAnchorMoves;
begin
  mMoves := TAtlasBreakpointAnchors.Reversed([TAtlasAnchorMove.Create('a.pas', 7, 17),
    TAtlasAnchorMove.Create('a.pas', 12, 22)]);
  Assert.AreEqual(2, Integer(Length(mMoves)));
  // Zurück nach oben: die oberste zuerst.
  Assert.AreEqual(17, mMoves[0].FromLine);
  Assert.AreEqual(7, mMoves[0].ToLine);
  Assert.AreEqual(22, mMoves[1].FromLine);
  Assert.AreEqual(12, mMoves[1].ToLine);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointAnchorsTests);

end.
