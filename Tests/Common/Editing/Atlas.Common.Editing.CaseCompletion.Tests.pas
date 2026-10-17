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
    /// <summary>#50: „case vervollständigen“ auf einer fertigen case-Anweisung.</summary>
    [Test]
    procedure CompletesWholeCaseStatement;
    /// <summary>#50: Mit else-Teil kommen die Werte davor; Präfix und Fälle ohne Angebot.</summary>
    [Test]
    procedure CompletesBeforeElseAndRejects;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
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

const
  Aligns: array[0..6] of string = ('alNone', 'alTop', 'alBottom', 'alLeft', 'alRight', 'alClient', 'alCustom');

function AlignValues: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Aligns));
  for Index := 0 to High(Aligns) do
    Result[Index] := Aligns[Index];
end;

/// <summary>Ergebnis von Complete für die case-Anweisung in Zeile 1 von AText; '-' ohne Angebot.</summary>
function CompleteText(const AText, APrefix: string; out ACount: Integer; out AHasElse: Boolean): string;
var
  Tree: TSyntaxTree;
  CaseNode: TSyntaxNode;
  Edits: TArray<TTextEdit>;
begin
  ACount := 0;
  AHasElse := False;
  Tree := TPascalParser.Parse(AText);
  try
    CaseNode := TCaseCompletion.CaseAt(Tree, TTextPosition.Create(3, 4));
    if (CaseNode = nil) or not TCaseCompletion.Complete(AText, Tree, CaseNode, AlignValues, APrefix, Edits, ACount,
      AHasElse) then
      Exit('-');
    Result := TChangeSignature.ApplyEdits(AText, Edits);
  finally
    Tree.Free;
  end;
end;

procedure TCaseCompletionTests.CompletesWholeCaseStatement;
var
  Count: Integer;
  HasElse: Boolean;
begin
  // Abnahmefall: TAlign mit drei vorhandenen Werten, vier fehlen; das ";" hinter dem letzten Zweig kommt dazu.
  Assert.AreEqual(
    'procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    alNone: X;'#10'    alTop, alBottom: Y;'#10 +
    '    alLeft: ;'#10'    alRight: ;'#10'    alClient: ;'#10'    alCustom: ;'#10'  end;'#10'end;'#10,
    CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    alNone: X;'#10'    alTop, alBottom: Y'#10 +
    '  end;'#10'end;'#10, '', Count, HasElse));
  Assert.AreEqual(4, Count);
  Assert.IsFalse(HasElse);
end;

procedure TCaseCompletionTests.CompletesBeforeElseAndRejects;
var
  Count: Integer;
  HasElse: Boolean;
  All: string;
  Index: Integer;
begin
  Assert.AreEqual(
    'procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    TAlign.alNone: X;'#10'    TAlign.alTop: ;'#10 +
    '    TAlign.alBottom: ;'#10'    TAlign.alLeft: ;'#10'    TAlign.alRight: ;'#10'    TAlign.alClient: ;'#10 +
    '    TAlign.alCustom: ;'#10'  else'#10'    Z;'#10'  end;'#10'end;'#10,
    CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    TAlign.alNone: X;'#10'  else'#10 +
    '    Z;'#10'  end;'#10'end;'#10, 'TAlign.', Count, HasElse));
  Assert.AreEqual(6, Count);
  Assert.IsTrue(HasElse);
  // Nichts fehlt: keine Aktion.
  All := '';
  for Index := 0 to High(Aligns) do
    All := All + '    ' + Aligns[Index] + ': ;'#10;
  Assert.AreEqual('-', CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10 + All + '  end;'#10 +
    'end;'#10, '', Count, HasElse));
  // Eine Marke, die kein Wert ist.
  Assert.AreEqual('-', CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    1: X;'#10'  end;'#10 +
    'end;'#10, '', Count, HasElse));
end;

initialization
  TDUnitX.RegisterTestFixture(TCaseCompletionTests);

end.
