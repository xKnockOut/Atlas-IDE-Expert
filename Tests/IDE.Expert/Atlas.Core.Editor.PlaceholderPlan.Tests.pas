unit Atlas.Core.Editor.PlaceholderPlan.Tests;

// Entscheidungen des Platzhalter-Modus (Atlas.Core.Editor.PlaceholderPlan): Tasten, Cursor nach Angleichungen,
// Undo-Schritt, Rahmen und Fußzeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPlaceholderPlanTests = class
  public
    [Test]
    procedure KeysOnlyWhileActive;
    [Test]
    procedure KeysWithOtherShiftNotTaken;
    [Test]
    procedure CursorShiftCountsEditsBefore;
    [Test]
    procedure ReplacementKeepsCommonEnds;
    [Test]
    procedure ReplacementOfEqualTexts;
    [Test]
    procedure FrameByNumberAndStart;
    [Test]
    procedure SpanOnlyOnStartLine;
    [Test]
    procedure FooterOnLineOfCurrent;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Completion.Placeholders,
  Atlas.Core.Editor.PlaceholderPlan;

function Field(ANumber, AStart, ALength: Integer): TAtlasPlaceholderField;
begin
  Result.Number := ANumber;
  Result.Start := AStart;
  Result.Length := ALength;
end;

function Edit(AStart, AStop: Integer; const AText: string): TAtlasPlaceholderEdit;
begin
  Result := Default(TAtlasPlaceholderEdit);
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Text := AText;
end;

{ TPlaceholderPlanTests }

procedure TPlaceholderPlanTests.KeysOnlyWhileActive;
begin
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.Next,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkTab, [], True));
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.Previous,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkTab, [ssShift], True));
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.Accept,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkReturn, [], True));
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.Cancel,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkEscape, [], True));
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.None,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkTab, [], False));
end;

procedure TPlaceholderPlanTests.KeysWithOtherShiftNotTaken;
begin
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.None,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkTab, [ssCtrl], True));
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.None,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkReturn, [ssShift], True));
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.None,
    TAtlasPlaceholderPlan.Key(TAtlasPlaceholderPlan.cVkEscape, [ssAlt], True));
  Assert.AreEqual<TAtlasPlaceholderKey>(TAtlasPlaceholderKey.None, TAtlasPlaceholderPlan.Key(Ord('A'), [], True));
end;

procedure TPlaceholderPlanTests.CursorShiftCountsEditsBefore;
var
  mEdits: TAtlasPlaceholderEdits;
begin
  mEdits := TArray<TAtlasPlaceholderEdit>.Create(Edit(2, 4, 'Name'), Edit(10, 12, 'Name'));
  // Nur die Angleichung vor dem Cursor (Ende bis zum Cursor) verschiebt ihn.
  Assert.AreEqual(2, TAtlasPlaceholderPlan.CursorShift(mEdits, 4));
  Assert.AreEqual(0, TAtlasPlaceholderPlan.CursorShift(mEdits, 3));
  Assert.AreEqual(4, TAtlasPlaceholderPlan.CursorShift(mEdits, 20));
  Assert.AreEqual(0, TAtlasPlaceholderPlan.CursorShift(nil, 20));
end;

procedure TPlaceholderPlanTests.ReplacementKeepsCommonEnds;
var
  mReplacement: TAtlasPlaceholderReplacement;
begin
  mReplacement := TAtlasPlaceholderPlan.Replacement('begin end', 'begin x := 1; end');
  Assert.AreEqual(6, mReplacement.Prefix);
  Assert.AreEqual(3, mReplacement.Suffix);
  // Anfang und Ende überlappen nicht.
  mReplacement := TAtlasPlaceholderPlan.Replacement('aa', 'aaa');
  Assert.AreEqual(2, mReplacement.Prefix);
  Assert.AreEqual(0, mReplacement.Suffix);
end;

procedure TPlaceholderPlanTests.ReplacementOfEqualTexts;
var
  mReplacement: TAtlasPlaceholderReplacement;
begin
  mReplacement := TAtlasPlaceholderPlan.Replacement('abc', 'abc');
  Assert.AreEqual(3, mReplacement.Prefix);
  Assert.AreEqual(0, mReplacement.Suffix);
  mReplacement := TAtlasPlaceholderPlan.Replacement('', 'x');
  Assert.AreEqual(0, mReplacement.Prefix);
  Assert.AreEqual(0, mReplacement.Suffix);
end;

procedure TPlaceholderPlanTests.FrameByNumberAndStart;
var
  mCurrent: TAtlasPlaceholderField;
begin
  mCurrent := Field(1, 5, 3);
  Assert.AreEqual<TAtlasPlaceholderFrame>(TAtlasPlaceholderFrame.Current,
    TAtlasPlaceholderPlan.FrameOf(Field(1, 5, 3), mCurrent));
  Assert.AreEqual<TAtlasPlaceholderFrame>(TAtlasPlaceholderFrame.Linked,
    TAtlasPlaceholderPlan.FrameOf(Field(1, 20, 3), mCurrent));
  Assert.AreEqual<TAtlasPlaceholderFrame>(TAtlasPlaceholderFrame.Other,
    TAtlasPlaceholderPlan.FrameOf(Field(2, 5, 3), mCurrent));
end;

procedure TPlaceholderPlanTests.SpanOnlyOnStartLine;
const
  cText = 'for i := 0 to'#13#10'  Count do';
var
  mSpan: TAtlasPlaceholderSpan;
begin
  Assert.IsTrue(TAtlasPlaceholderPlan.SpanOn(cText, Field(1, 4, 1), 0, 'for i := 0 to', mSpan));
  Assert.AreEqual(4, mSpan.Start);
  Assert.AreEqual(5, mSpan.Stop);
  Assert.IsFalse(TAtlasPlaceholderPlan.SpanOn(cText, Field(1, 4, 1), 1, '  Count do', mSpan));
  // Reicht der Platzhalter in die nächste Zeile, endet der Teil am Zeilenende.
  Assert.IsTrue(TAtlasPlaceholderPlan.SpanOn(cText, Field(1, 11, 10), 0, 'for i := 0 to', mSpan));
  Assert.AreEqual(11, mSpan.Start);
  Assert.AreEqual(13, mSpan.Stop);
end;

procedure TPlaceholderPlanTests.FooterOnLineOfCurrent;
const
  cText = 'a'#10'  b';
begin
  Assert.IsTrue(TAtlasPlaceholderPlan.FooterOn(cText, Field(1, 4, 1), 1));
  Assert.IsFalse(TAtlasPlaceholderPlan.FooterOn(cText, Field(1, 4, 1), 0));
  Assert.AreEqual(3 + 1 + TAtlasPlaceholderPlan.cFooterGap, TAtlasPlaceholderPlan.FooterColumn('a'#9'b', 2));
  Assert.AreEqual(1 + TAtlasPlaceholderPlan.cFooterGap, TAtlasPlaceholderPlan.FooterColumn('', 4));
end;

end.
