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
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.CaseCompletion;

const
  cValues: array[0..3] of string = ('skCircle', 'skLine', 'skRect', 'skTriangle');

function AllValues: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cValues));
  for mIndex := 0 to High(cValues) do
  begin
    Result[mIndex] := cValues[mIndex];
  end;
end;

/// <summary>Zweig-Stelle am "|" in AMarked.</summary>
function SlotAt(const AMarked: string; out ASlot: TCaseBranchSlot): Boolean;
var
  mIndex, mLine, mCharacter: Integer;
  mText: string;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  mText := StringReplace(AMarked, '|', '', []);
  Result := TCaseCompletion.BranchSlot(mText, TPascalLexer.Tokenize(mText), TTextPosition.Create(mLine, mCharacter),
    ASlot);
end;

/// <summary>Neue Zweige am "|"; '-' ohne Zweig-Stelle.</summary>
function Branches(const AMarked: string; const APrefix: string): string; overload;
var
  mSlot: TCaseBranchSlot;
  mMissing: TArray<string>;
begin
  if not SlotAt(AMarked, mSlot) then
  begin
    Exit('-');
  end;
  Assert.IsTrue(TCaseCompletion.Missing(AllValues, mSlot.Labels, mMissing));
  Result := TCaseCompletion.BranchesText(mSlot, mMissing, APrefix, #10);
end;

function Branches(const AMarked: string): string; overload;
begin
  Result := Branches(AMarked, '');
end;

{ TCaseCompletionTests }

procedure TCaseCompletionTests.InsertsAllBranchesAndMissingEnd;
var
  mSlot: TCaseBranchSlot;
begin
  // Das "end" am Zeilenanfang gehört zur Routine: das der case-Anweisung fehlt.
  Assert.AreEqual(#10'    skCircle: $0;'#10'    skLine: ;'#10'    skRect: ;'#10'    skTriangle: ;'#10'  end;',
    Branches('begin'#10'  case Shape.Kind of'#10'    |'#10'end;'));
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    |'#10'end;', mSlot));
  Assert.IsFalse(mSlot.HasEnd);
  // Ersetzt den Leerraum ab "of" bis zum Cursor.
  Assert.AreEqual(1, mSlot.EditRange.StartPos.Line);
  Assert.AreEqual(20, mSlot.EditRange.StartPos.Character);
  Assert.AreEqual(2, mSlot.EditRange.EndPos.Line);
  Assert.AreEqual(4, mSlot.EditRange.EndPos.Character);
  // Mit eigenem end kein zweites; Cursor direkt hinter "of".
  Assert.AreEqual(#10'    skCircle: $0;'#10'    skLine: ;'#10'    skRect: ;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of|'#10'  end;'#10'end;'));
end;

procedure TCaseCompletionTests.AddsOnlyMissingBranches;
var
  mSlot: TCaseBranchSlot;
begin
  Assert.AreEqual(#10'    skLine: $0;'#10'    skRect: ;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: Zeichne;'#10'    |'#10'  end;'#10'end;'));
  // Das getippte Wort zählt nicht und wird mit ersetzt.
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    skCircle: Zeichne;'#10'    sk|'#10'  end;'#10'end;', mSlot));
  Assert.AreEqual(1, Integer(Length(mSlot.Labels)));
  Assert.AreEqual(6, mSlot.EditRange.EndPos.Character);
  // Zweige mit begin … end, if … else und repeat … until.
  Assert.AreEqual(#10'    skRect: $0;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: begin A; B; end;'#10 +
    '    skLine: if A then B else C;'#10'    |'#10'  end;'#10'end;'));
  Assert.AreEqual(#10'    skLine: $0;'#10'    skRect: ;'#10'    skTriangle: ;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle: repeat A; until B;'#10'    |'#10'  end;'#10'end;'));
end;

procedure TCaseCompletionTests.RangesAndListsCountAsPresent;
var
  mSlot: TCaseBranchSlot;
  mMissing: TArray<string>;
begin
  Assert.AreEqual(#10'    skTriangle: $0;',
    Branches('begin'#10'  case Shape.Kind of'#10'    skCircle..skLine, skRect: ;'#10'    |'#10'  end;'#10'end;'));
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    skCircle..skRect, skTriangle: ;'#10'    |'#10 +
    '  end;'#10'end;', mSlot));
  Assert.IsTrue(TCaseCompletion.Missing(AllValues, mSlot.Labels, mMissing));
  Assert.AreEqual(0, Integer(Length(mMissing)));
  // Marken, die keine Werte sind (Zahlen, andere Typen): nichts anbieten.
  Assert.IsTrue(SlotAt('begin'#10'  case I of'#10'    1: ;'#10'    |'#10'  end;'#10'end;', mSlot));
  Assert.IsFalse(TCaseCompletion.Missing(AllValues, mSlot.Labels, mMissing));
end;

procedure TCaseCompletionTests.AddsEndBehindFollowingBranches;
var
  mSlot: TCaseBranchSlot;
  mMissing: TArray<string>;
begin
  // Hinter dem Cursor folgen Zweige: die neuen am Cursor, das fehlende end hinter dem letzten Zweig.
  Assert.IsTrue(SlotAt('begin'#10'  case Shape.Kind of'#10'    |'#10'    skLine, skTriangle: Zeichne;'#10'end;', mSlot));
  Assert.IsTrue(mSlot.Following);
  Assert.IsFalse(mSlot.HasEnd);
  Assert.IsTrue(TCaseCompletion.Missing(AllValues, mSlot.Labels, mMissing));
  Assert.AreEqual(#10'    skCircle: $0;'#10'    skRect: ;', TCaseCompletion.BranchesText(mSlot, mMissing, '', #10));
  Assert.AreEqual(#10'  end;', TCaseCompletion.EndText(mSlot, #10));
  Assert.AreEqual(3, mSlot.EndInsert.Line);
  Assert.AreEqual(32, mSlot.EndInsert.Character);
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
  cAligns: array[0..6] of string = ('alNone', 'alTop', 'alBottom', 'alLeft', 'alRight', 'alClient', 'alCustom');

function AlignValues: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cAligns));
  for mIndex := 0 to High(cAligns) do
  begin
    Result[mIndex] := cAligns[mIndex];
  end;
end;

/// <summary>Ergebnis von Complete für die case-Anweisung in Zeile 1 von AText; '-' ohne Angebot.</summary>
function CompleteText(const AText, APrefix: string; out ACount: Integer; out AHasElse: Boolean): string;
var
  mTree: TSyntaxTree;
  mCaseNode: TSyntaxNode;
  mCompletion: TCaseCompletionEdits;
begin
  ACount := 0;
  AHasElse := False;
  mTree := TPascalParser.Parse(AText);
  try
    mCaseNode := TCaseCompletion.CaseAt(mTree, TTextPosition.Create(3, 4));
    if (mCaseNode = nil) or not TCaseCompletion.Complete(AText, mTree, mCaseNode, AlignValues, APrefix,
      mCompletion) then
    begin
      Exit('-');
    end;
    ACount := mCompletion.Count;
    AHasElse := mCompletion.HasElse;
    Result := TChangeSignature.ApplyEdits(AText, mCompletion.Edits);
  finally
    mTree.Free;
  end;
end;

procedure TCaseCompletionTests.CompletesWholeCaseStatement;
var
  mCount: Integer;
  mHasElse: Boolean;
begin
  // Abnahmefall: TAlign mit drei vorhandenen Werten, vier fehlen; das ";" hinter dem letzten Zweig kommt dazu.
  Assert.AreEqual(
    'procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    alNone: X;'#10'    alTop, alBottom: Y;'#10 +
    '    alLeft: ;'#10'    alRight: ;'#10'    alClient: ;'#10'    alCustom: ;'#10'  end;'#10'end;'#10,
    CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    alNone: X;'#10'    alTop, alBottom: Y'#10 +
    '  end;'#10'end;'#10, '', mCount, mHasElse));
  Assert.AreEqual(4, mCount);
  Assert.IsFalse(mHasElse);
end;

procedure TCaseCompletionTests.CompletesBeforeElseAndRejects;
var
  mCount: Integer;
  mHasElse: Boolean;
  mAll: string;
  mIndex: Integer;
begin
  Assert.AreEqual(
    'procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    TAlign.alNone: X;'#10'    TAlign.alTop: ;'#10 +
    '    TAlign.alBottom: ;'#10'    TAlign.alLeft: ;'#10'    TAlign.alRight: ;'#10'    TAlign.alClient: ;'#10 +
    '    TAlign.alCustom: ;'#10'  else'#10'    Z;'#10'  end;'#10'end;'#10,
    CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    TAlign.alNone: X;'#10'  else'#10 +
    '    Z;'#10'  end;'#10'end;'#10, 'TAlign.', mCount, mHasElse));
  Assert.AreEqual(6, mCount);
  Assert.IsTrue(mHasElse);
  // Nichts fehlt: keine Aktion.
  mAll := '';
  for mIndex := 0 to High(cAligns) do
  begin
    mAll := mAll + '    ' + cAligns[mIndex] + ': ;'#10;
  end;
  Assert.AreEqual('-', CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10 + mAll + '  end;'#10 +
    'end;'#10, '', mCount, mHasElse));
  // Eine Marke, die kein Wert ist.
  Assert.AreEqual('-', CompleteText('procedure P(A: TAlign);'#10'begin'#10'  case A of'#10'    1: X;'#10'  end;'#10 +
    'end;'#10, '', mCount, mHasElse));
end;

initialization
  TDUnitX.RegisterTestFixture(TCaseCompletionTests);

end.
