unit Atlas.Common.Editing.CaseCompletion.Tests;

// Tests für den Erzeuger fehlender case-Zweige (#449).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCaseCompletionTests = class
  public
    [Test]
    procedure InsertsAllBranchesAndMissingEnd;
    [Test]
    procedure AddsOnlyMissingBranches;
    [Test]
    procedure RangesAndListsCountAsPresent;
    [Test]
    procedure AddsEndBehindFollowingBranches;
    [Test]
    procedure KeepsBranchIndentAndScopedPrefix;
    [Test]
    procedure IgnoresOtherPlaces;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.CaseCompletion;

const
  Values: array[0..3] of string = ('skCircle', 'skLine', 'skRect', 'skTriangle');

function AllValues: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Values));
  for Index := 0 to High(Values) do
    Result[Index] := Values[Index];
end;

/// <summary>Zweig-Stelle am "|" in AMarked.</summary>
function SlotAt(const AMarked: string; out ASlot: TCaseBranchSlot): Boolean;
var
  Index, Line, Character: Integer;
  Text: string;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  Text := StringReplace(AMarked, '|', '', []);
  Result := TCaseCompletion.BranchSlot(Text, TPascalLexer.Tokenize(Text), TTextPosition.Create(Line, Character), ASlot);
end;

/// <summary>Neue Zweige am "|"; '-' ohne Zweig-Stelle.</summary>
function Branches(const AMarked: string; const APrefix: string = ''): string;
var
  Slot: TCaseBranchSlot;
  Missing: TArray<string>;
begin
  if not SlotAt(AMarked, Slot) then
    Exit('-');
  Assert.IsTrue(TCaseCompletion.Missing(AllValues, Slot.Labels, Missing));
  Result := TCaseCompletion.BranchesText(Slot, Missing, APrefix, #10);
end;

{ TCaseCompletionTests }

procedure TCaseCompletionTests.InsertsAllBranchesAndMissingEnd;
var
  Slot: TCaseBranchSlot;
begin
  // Das "end" am Zeilenanfang gehört zur Routine: das der case-Anweisung fehlt.
  Assert.AreEqual(#10'    skCircle: $0;'#10'    skLine: ;'#10'    skRect: ;'#10'    skTriangle: ;'#10'  end;',
    Branches('begin'#10'  case Shape.Kind of'#10'    |'#10'end;'));
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    |'#10'end;', Slot));
  Assert.IsFalse(Slot.HasEnd);
  // Ersetzt den Leerraum ab "of" bis zum Cursor.
  Assert.AreEqual(1, Slot.EditRange.StartPos.Line);
  Assert.AreEqual(20, Slot.EditRange.StartPos.Character);
  Assert.AreEqual(2, Slot.EditRange.EndPos.Line);
  Assert.AreEqual(4, Slot.EditRange.EndPos.Character);
  // Mit eigenem end kein zweites; Cursor direkt hinter "of".
  Assert.AreEqual(#10'    skCircle: $0;'#10'    skLine: ;'#10'    skRect: ;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of|'#10'  end;'#10'end;'));
end;

procedure TCaseCompletionTests.AddsOnlyMissingBranches;
var
  Slot: TCaseBranchSlot;
begin
  Assert.AreEqual(#10'    skLine: $0;'#10'    skRect: ;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: Zeichne;'#10'    |'#10'  end;'#10'end;'));
  // Das getippte Wort zählt nicht und wird mit ersetzt.
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    skCircle: Zeichne;'#10'    sk|'#10'  end;'#10'end;', Slot));
  Assert.AreEqual(1, Integer(Length(Slot.Labels)));
  Assert.AreEqual(6, Slot.EditRange.EndPos.Character);
  // Zweige mit begin … end, if … else und repeat … until.
  Assert.AreEqual(#10'    skRect: $0;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: begin A; B; end;'#10 +
    '    skLine: if A then B else C;'#10'    |'#10'  end;'#10'end;'));
  Assert.AreEqual(#10'    skLine: $0;'#10'    skRect: ;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: repeat A; until B;'#10'    |'#10'  end;'#10'end;'));
end;

procedure TCaseCompletionTests.RangesAndListsCountAsPresent;
var
  Slot: TCaseBranchSlot;
  Missing: TArray<string>;
begin
  Assert.AreEqual(#10'    skTriangle: $0;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle..skLine, skRect: ;'#10'    |'#10'  end;'#10'end;'));
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    skCircle..skRect, skTriangle: ;'#10'    |'#10 +
    '  end;'#10'end;', Slot));
  Assert.IsTrue(TCaseCompletion.Missing(AllValues, Slot.Labels, Missing));
  Assert.AreEqual(0, Integer(Length(Missing)));
  // Marken, die keine Werte sind (Zahlen, andere Typen): nichts anbieten.
  Assert.IsTrue(SlotAt('begin'#10'  case I of'#10'    1: ;'#10'    |'#10'  end;'#10'end;', Slot));
  Assert.IsFalse(TCaseCompletion.Missing(AllValues, Slot.Labels, Missing));
end;

procedure TCaseCompletionTests.AddsEndBehindFollowingBranches;
var
  Slot: TCaseBranchSlot;
  Missing: TArray<string>;
begin
  // Hinter dem Cursor folgen Zweige: die neuen am Cursor, das fehlende end hinter dem letzten Zweig.
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    |'#10'    skLine, skTriangle: Zeichne;'#10'end;', Slot));
  Assert.IsTrue(Slot.Following);
  Assert.IsFalse(Slot.HasEnd);
  Assert.IsTrue(TCaseCompletion.Missing(AllValues, Slot.Labels, Missing));
  Assert.AreEqual(#10'    skCircle: $0;'#10'    skRect: ;', TCaseCompletion.BranchesText(Slot, Missing, '', #10));
  Assert.AreEqual(#10'  end;', TCaseCompletion.EndText(Slot, #10));
  Assert.AreEqual(3, Slot.EndInsert.Line);
  Assert.AreEqual(32, Slot.EndInsert.Character);
  // Vor dem else-Teil: Zweige davor, end vorhanden.
  Assert.AreEqual(#10'    skLine: $0;'#10'    skRect: ;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: A;'#10'    |'#10'  else'#10'    B;'#10'  end;'#10'end;'));
end;

procedure TCaseCompletionTests.KeepsBranchIndentAndScopedPrefix;
begin
  // Einrückung wie der vorhandene Zweig, Typpräfix bei {$SCOPEDENUMS ON}; vorhandene Marken auch qualifiziert.
  Assert.AreEqual(#10#9'TShapeKind.skCircle: $0;'#10#9'TShapeKind.skRect: ;'#10#9'TShapeKind.skTriangle: ;',
    Branches('begin'#10'case Kind of'#10#9'TShapeKind.skLine: A;'#10#9'|'#10'end;'#10'end;', 'TShapeKind.'));
end;

procedure TCaseCompletionTests.IgnoresOtherPlaces;
begin
  // Im else-Teil, in einem begin-Block eines Zweigs und außerhalb von case.
  Assert.AreEqual('-', Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: A;'#10'  else'#10'    B;'#10'    |'#10 +
    '  end;'#10'end;'));
  Assert.AreEqual('-', Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: begin A;| end;'#10'  end;'#10'end;'));
  Assert.AreEqual('-', Branches('begin'#10'  A := 1;'#10'  |'#10'end;'));
  // Mitten in einer Liste "skCircle, |" ergänzt Atlas nur einzelne Werte.
  Assert.AreEqual('-', Branches('begin'#10'  case Shape.Kind of'#10'    skCircle, |'#10'  end;'#10'end;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TCaseCompletionTests);

end.
