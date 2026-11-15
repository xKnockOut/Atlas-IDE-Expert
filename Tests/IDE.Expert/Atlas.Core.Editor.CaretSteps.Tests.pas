unit Atlas.Core.Editor.CaretSteps.Tests;

// Eigene Schritte bei mehreren Einfügemarken (#589): Rückgängig und Wiederholen bringen die Marken zurück.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.CaretSteps;

type
  [TestFixture]
  TAtlasCaretStepsTests = class
  private
    FSteps: TAtlasCaretSteps;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UndoRecallsTheCaretsBefore;
    [Test]
    procedure RedoRecallsTheCaretsAfter;
    [Test]
    procedure ForeignTextRecallsNothing;
    [Test]
    procedure NewStepDropsWhatCouldBeRedone;
    [Test]
    procedure OnlyTheLastStepsAreKept;
    [Test]
    procedure RecalledCaretsAreACopy;
    [Test]
    procedure RangesRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.MultiCursor;

function Carets(ALine, ACharacter: Integer): TAtlasCarets;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := TAtlasCaret.Range(ALine, ACharacter, ALine, ACharacter);
  Result[1] := TAtlasCaret.Range(ALine + 1, ACharacter, ALine + 1, ACharacter);
end;

{ TAtlasCaretStepsTests }

procedure TAtlasCaretStepsTests.Setup;
begin
  FSteps.Clear;
end;

procedure TAtlasCaretStepsTests.TearDown;
begin
  FSteps.Clear;
end;

procedure TAtlasCaretStepsTests.UndoRecallsTheCaretsBefore;
var
  mCarets: TAtlasCarets;
begin
  FSteps.Add('a', 'ab', Carets(0, 1), Carets(0, 2));
  Assert.IsTrue(FSteps.Recall('a', mCarets));
  Assert.AreEqual(Integer(2), Integer(Length(mCarets)));
  Assert.AreEqual(1, mCarets[0].Character);
  Assert.AreEqual(0, FSteps.Index);
  Assert.IsFalse(FSteps.Recall('x', mCarets));
  Assert.AreEqual(Integer(0), Integer(Length(mCarets)));
end;

procedure TAtlasCaretStepsTests.RedoRecallsTheCaretsAfter;
var
  mCarets: TAtlasCarets;
begin
  FSteps.Add('a', 'ab', Carets(0, 1), Carets(0, 2));
  FSteps.Add('ab', 'abc', Carets(0, 2), Carets(0, 3));
  Assert.IsTrue(FSteps.Recall('ab', mCarets), 'Rückgängig');
  Assert.AreEqual(2, mCarets[0].Character);
  Assert.IsTrue(FSteps.Recall('abc', mCarets), 'Wiederholen');
  Assert.AreEqual(3, mCarets[0].Character);
  Assert.AreEqual(2, FSteps.Index);
end;

procedure TAtlasCaretStepsTests.ForeignTextRecallsNothing;
var
  mCarets: TAtlasCarets;
begin
  Assert.IsFalse(FSteps.Recall('', mCarets), 'ohne Schritte');
  FSteps.Add('a', 'ab', Carets(0, 1), Carets(0, 2));
  Assert.IsFalse(FSteps.Recall('ab', mCarets), 'Stand nach dem letzten Schritt ist kein Wiederholen');
  Assert.AreEqual(1, FSteps.Index);
end;

procedure TAtlasCaretStepsTests.NewStepDropsWhatCouldBeRedone;
var
  mCarets: TAtlasCarets;
begin
  FSteps.Add('a', 'ab', Carets(0, 1), Carets(0, 2));
  FSteps.Add('ab', 'abc', Carets(0, 2), Carets(0, 3));
  FSteps.Recall('ab', mCarets);
  FSteps.Add('ab', 'abX', Carets(0, 2), Carets(0, 3));
  Assert.AreEqual(2, FSteps.Count);
  Assert.IsFalse(FSteps.Recall('abc', mCarets), 'der verworfene Schritt kommt nicht wieder');
end;

procedure TAtlasCaretStepsTests.OnlyTheLastStepsAreKept;
var
  mIndex: Integer;
  mCarets: TAtlasCarets;
begin
  for mIndex := 0 to TAtlasCaretSteps.cLimit + 4 do
  begin
    FSteps.Add('s' + IntToStr(mIndex), 's' + IntToStr(mIndex + 1), Carets(mIndex, 0), Carets(mIndex, 1));
  end;
  Assert.AreEqual(TAtlasCaretSteps.cLimit, FSteps.Count);
  Assert.AreEqual(TAtlasCaretSteps.cLimit, FSteps.Index);
  Assert.IsTrue(FSteps.Recall('s' + IntToStr(TAtlasCaretSteps.cLimit + 4), mCarets));
end;

procedure TAtlasCaretStepsTests.RecalledCaretsAreACopy;
var
  mCarets, mAgain: TAtlasCarets;
begin
  FSteps.Add('a', 'ab', Carets(0, 1), Carets(0, 2));
  FSteps.Recall('a', mCarets);
  mCarets[0] := TAtlasCaret.Range(9, 9, 9, 9);
  FSteps.Recall('ab', mAgain);
  FSteps.Recall('a', mAgain);
  Assert.AreEqual(1, mAgain[0].Character);
end;

procedure TAtlasCaretStepsTests.RangesRoundTrip;
var
  mCarets: TAtlasCarets;
  mRanges: TArray<TLspRange>;
begin
  mCarets := nil;
  SetLength(mCarets, 1);
  // Markierung rückwärts: Anker hinter dem Cursor.
  mCarets[0] := TAtlasCaret.Range(2, 8, 1, 4);
  mRanges := TAtlasCaretRanges.RangesOf(mCarets);
  Assert.AreEqual(1, mRanges[0].StartPos.Line);
  Assert.AreEqual(4, mRanges[0].StartPos.Character);
  Assert.AreEqual(2, mRanges[0].EndPos.Line);
  Assert.AreEqual(8, mRanges[0].EndPos.Character);
  mCarets := TAtlasCaretRanges.CaretsOf(mRanges);
  Assert.AreEqual(2, mCarets[0].Line, 'Cursor am Ende');
  Assert.AreEqual(8, mCarets[0].Character);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCaretStepsTests);

end.
