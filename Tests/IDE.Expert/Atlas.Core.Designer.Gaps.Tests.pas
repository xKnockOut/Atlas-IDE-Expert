unit Atlas.Core.Designer.Gaps.Tests;

// Tests der Abstandsgriffe im Designer (#734): Reihen- und Spaltenerkennung,
// alle Ankerpunkte, Einrasten, abweichende Abstände und Überlauf aus dem
// Parent.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Designer.Gaps;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasGapsTests = class
  private
    FRow: TArray<TRect>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DetectsRowInAnyOrder;
    [Test]
    procedure DetectsColumn;
    [Test]
    procedure MixedHasNoAxis;
    [Test]
    procedure OverlappingHasNoAxis;
    [Test]
    procedure SingleHasNoAxis;
    [Test]
    procedure CenterKeepsMiddle;
    [Test]
    procedure FirstStays;
    [Test]
    procedure LastStays;
    [Test]
    procedure ColumnMovesTopOnly;
    [Test]
    procedure SnapsNearValues;
    [Test]
    procedure DeviatingGaps;
    [Test]
    procedure OutsideParent;
    [Test]
    procedure ParsesValuesAndAnchor;
  end;

implementation

procedure TAtlasGapsTests.Setup;
begin
  // Vier Steuerelemente in einer Reihe mit Abständen 7, 15 und 10 (unsortiert übergeben).
  FRow := [Rect(100, 12, 160, 33), Rect(10, 10, 50, 31), Rect(57, 14, 85, 30), Rect(170, 10, 230, 31)];
end;

procedure TAtlasGapsTests.TearDown;
begin
  FRow := nil;
end;

procedure TAtlasGapsTests.DetectsRowInAnyOrder;
var
  mLayout: TAtlasGapLayout;
begin
  mLayout := TAtlasGaps.Detect(FRow);
  Assert.AreEqual(Ord(TAtlasGapAxis.Row), Ord(mLayout.Axis));
  Assert.AreEqual(4, Integer(Length(mLayout.Order)));
  Assert.AreEqual(1, mLayout.Order[0]);
  Assert.AreEqual(2, mLayout.Order[1]);
  Assert.AreEqual(0, mLayout.Order[2]);
  Assert.AreEqual(3, mLayout.Order[3]);
  Assert.AreEqual(7, mLayout.Gaps[0]);
  Assert.AreEqual(15, mLayout.Gaps[1]);
  Assert.AreEqual(10, mLayout.Gaps[2]);
end;

procedure TAtlasGapsTests.DetectsColumn;
var
  mLayout: TAtlasGapLayout;
begin
  mLayout := TAtlasGaps.Detect([Rect(10, 50, 90, 70), Rect(10, 10, 120, 31), Rect(20, 80, 100, 100)]);
  Assert.AreEqual(Ord(TAtlasGapAxis.Column), Ord(mLayout.Axis));
  Assert.AreEqual(1, mLayout.Order[0]);
  Assert.AreEqual(19, mLayout.Gaps[0]);
  Assert.AreEqual(10, mLayout.Gaps[1]);
end;

procedure TAtlasGapsTests.MixedHasNoAxis;
begin
  // Zwei nebeneinander, eins darunter: weder Reihe noch Spalte.
  Assert.AreEqual(Ord(TAtlasGapAxis.None),
    Ord(TAtlasGaps.Detect([Rect(10, 10, 50, 30), Rect(60, 10, 100, 30), Rect(10, 40, 50, 60)]).Axis));
end;

procedure TAtlasGapsTests.OverlappingHasNoAxis;
begin
  Assert.AreEqual(Ord(TAtlasGapAxis.None), Ord(TAtlasGaps.Detect([Rect(10, 10, 50, 30), Rect(40, 12, 90, 28)]).Axis));
end;

procedure TAtlasGapsTests.SingleHasNoAxis;
begin
  Assert.AreEqual(Ord(TAtlasGapAxis.None), Ord(TAtlasGaps.Detect([Rect(10, 10, 50, 30)]).Axis));
end;

procedure TAtlasGapsTests.CenterKeepsMiddle;
var
  mNew: TArray<TRect>;
begin
  // Akzeptanzkriterium: dreimal 12 px, die Mitte der Gruppe (10 + 230) / 2 bleibt.
  mNew := TAtlasGaps.Respace(FRow, TAtlasGaps.Detect(FRow), 12, TAtlasGapAnchor.Center);
  Assert.AreEqual(8, mNew[1].Left);
  Assert.AreEqual(mNew[1].Right + 12, mNew[2].Left);
  Assert.AreEqual(mNew[2].Right + 12, mNew[0].Left);
  Assert.AreEqual(mNew[0].Right + 12, mNew[3].Left);
  Assert.AreEqual(232, mNew[3].Right);
  Assert.AreEqual(120, (mNew[1].Left + mNew[3].Right) div 2);
  // Größe und Höhe bleiben.
  Assert.AreEqual(60, mNew[0].Width);
  Assert.AreEqual(12, mNew[0].Top);
end;

procedure TAtlasGapsTests.FirstStays;
var
  mNew: TArray<TRect>;
begin
  mNew := TAtlasGaps.Respace(FRow, TAtlasGaps.Detect(FRow), 12, TAtlasGapAnchor.First);
  Assert.AreEqual(10, mNew[1].Left);
  Assert.AreEqual(234, mNew[3].Right);
end;

procedure TAtlasGapsTests.LastStays;
var
  mNew: TArray<TRect>;
begin
  mNew := TAtlasGaps.Respace(FRow, TAtlasGaps.Detect(FRow), 12, TAtlasGapAnchor.Last);
  Assert.AreEqual(230, mNew[3].Right);
  Assert.AreEqual(6, mNew[1].Left);
end;

procedure TAtlasGapsTests.ColumnMovesTopOnly;
var
  mRects, mNew: TArray<TRect>;
begin
  mRects := [Rect(10, 10, 90, 30), Rect(10, 35, 90, 55), Rect(30, 75, 90, 95)];
  mNew := TAtlasGaps.Respace(mRects, TAtlasGaps.Detect(mRects), 8, TAtlasGapAnchor.First);
  Assert.AreEqual(10, mNew[0].Top);
  Assert.AreEqual(38, mNew[1].Top);
  Assert.AreEqual(66, mNew[2].Top);
  Assert.AreEqual(30, mNew[2].Left);
  Assert.AreEqual(20, mNew[2].Height);
end;

procedure TAtlasGapsTests.SnapsNearValues;
var
  mValues: TArray<Integer>;
begin
  mValues := [4, 8, 12, 16];
  Assert.AreEqual(8, TAtlasGaps.Snap(9, mValues, TAtlasGaps.cSnapRange));
  Assert.AreEqual(8, TAtlasGaps.Snap(7, mValues, TAtlasGaps.cSnapRange));
  Assert.AreEqual(25, TAtlasGaps.Snap(25, mValues, TAtlasGaps.cSnapRange), 'zu weit weg');
  Assert.AreEqual(9, TAtlasGaps.Snap(9, nil, TAtlasGaps.cSnapRange), 'ohne Rastwerte');
end;

procedure TAtlasGapsTests.DeviatingGaps;
var
  mFlags: TArray<Boolean>;
begin
  mFlags := TAtlasGaps.Deviating([8, 8, 12, 8]);
  Assert.IsFalse(mFlags[0]);
  Assert.IsTrue(mFlags[2]);
  mFlags := TAtlasGaps.Deviating([6, 6]);
  Assert.IsFalse(mFlags[1], 'alle gleich');
end;

procedure TAtlasGapsTests.OutsideParent;
var
  mFlags: TArray<Boolean>;
  mNew: TArray<TRect>;
begin
  // Großer Abstand mit festem erstem Element schiebt das letzte aus dem Parent (Breite 300).
  mNew := TAtlasGaps.Respace(FRow, TAtlasGaps.Detect(FRow), 40, TAtlasGapAnchor.First);
  mFlags := TAtlasGaps.Outside(mNew, Rect(0, 0, 300, 200));
  Assert.IsFalse(mFlags[1]);
  Assert.IsTrue(mFlags[3]);
  mFlags := TAtlasGaps.Outside([Rect(-1, 0, 10, 10)], Rect(0, 0, 300, 200));
  Assert.IsTrue(mFlags[0], 'links heraus');
end;

procedure TAtlasGapsTests.ParsesValuesAndAnchor;
var
  mValues: TArray<Integer>;
begin
  mValues := TAtlasGaps.ParseValues('16, 4,8;x, 8 ,-2');
  Assert.AreEqual(3, Integer(Length(mValues)));
  Assert.AreEqual(4, mValues[0]);
  Assert.AreEqual(16, mValues[2]);
  Assert.AreEqual(Ord(TAtlasGapAnchor.First), Ord(TAtlasGaps.AnchorOf('First')));
  Assert.AreEqual(Ord(TAtlasGapAnchor.Last), Ord(TAtlasGaps.AnchorOf('last')));
  Assert.AreEqual(Ord(TAtlasGapAnchor.Center), Ord(TAtlasGaps.AnchorOf('egal')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGapsTests);

end.
