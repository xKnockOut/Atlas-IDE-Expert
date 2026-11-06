unit Atlas.Core.Hover.Items.Tests;

// Tests für den Rollbereich des Hover-Satzes (#1841): Grenze, Verschieben, Daumen.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Hover.Items;

type
  [TestFixture]
  THoverItemsTests = class
  public
    /// <summary>Kleinere der beiden Grenzen, mindestens drei Zeilen, 0 ohne Grenze.</summary>
    [Test]
    procedure LimitTakesSmallerBound;
    /// <summary>Fit kürzt die Sicht und begrenzt den Versatz.</summary>
    [Test]
    procedure FitClampsScroll;
    /// <summary>Shift verschiebt Bausteine, beschneidet und streicht Klickflächen.</summary>
    [Test]
    procedure ShiftDropsHiddenHits;
    /// <summary>Daumen oben, unten und mit Mindesthöhe.</summary>
    [Test]
    procedure ThumbFollowsScroll;
  end;

implementation

function Request(AMaxLines, ALimit, AScroll: Integer): TAtlasHoverScrollRequest;
begin
  Result := Default(TAtlasHoverScrollRequest);
  Result.MaxLines := AMaxLines;
  Result.Limit := ALimit;
  Result.Scroll := AScroll;
end;

function Hit(ATop, ABottom: Integer): TAtlasHoverHit;
begin
  Result := Default(TAtlasHoverHit);
  Result.Kind := TAtlasHoverHitKind.Published;
  Result.Rect := Rect(0, ATop, 50, ABottom);
end;

procedure THoverItemsTests.LimitTakesSmallerBound;
begin
  Assert.AreEqual(0, TAtlasHoverScroll.LimitOf(Request(0, 0, 0), 20));
  Assert.AreEqual(200, TAtlasHoverScroll.LimitOf(Request(10, 0, 0), 20));
  Assert.AreEqual(150, TAtlasHoverScroll.LimitOf(Request(10, 150, 0), 20));
  Assert.AreEqual(150, TAtlasHoverScroll.LimitOf(Request(0, 150, 0), 20));
  Assert.AreEqual(60, TAtlasHoverScroll.LimitOf(Request(1, 0, 0), 20), 'mindestens drei Zeilen');
end;

procedure THoverItemsTests.FitClampsScroll;
var
  mScroll: TAtlasHoverScroll;
begin
  mScroll := TAtlasHoverScroll.None;
  Assert.IsFalse(mScroll.Fit(Request(0, 0, 0), 100, 500, 300, 20));
  Assert.AreEqual(400, mScroll.Content);
  Assert.AreEqual(400, mScroll.View.Height);
  Assert.IsFalse(mScroll.Scrollable);
  mScroll := TAtlasHoverScroll.None;
  Assert.IsFalse(mScroll.Fit(Request(30, 0, 0), 100, 500, 300, 20), 'passt in 30 Zeilen');
  mScroll := TAtlasHoverScroll.None;
  Assert.IsTrue(mScroll.Fit(Request(5, 0, 1000), 100, 500, 300, 20));
  Assert.AreEqual(Integer(Rect(0, 100, 300, 200).Height), mScroll.View.Height);
  Assert.AreEqual(300, mScroll.MaxScroll);
  Assert.AreEqual(300, mScroll.Scroll);
  Assert.IsTrue(mScroll.Scrollable);
  mScroll := TAtlasHoverScroll.None;
  mScroll.Fit(Request(5, 0, -5), 100, 500, 300, 20);
  Assert.AreEqual(0, mScroll.Scroll);
end;

procedure THoverItemsTests.ShiftDropsHiddenHits;
var
  mScroll: TAtlasHoverScroll;
  mItems: TArray<TAtlasHoverItem>;
  mHits: TArray<TAtlasHoverHit>;
  mCount: Integer;
begin
  mScroll := TAtlasHoverScroll.None;
  mScroll.Fit(Request(5, 0, 50), 100, 500, 300, 20);
  SetLength(mItems, 3);
  mItems[0].Rect := Rect(0, 10, 10, 20);
  mItems[1].Rect := Rect(0, 120, 10, 140);
  mItems[2].Rect := Rect(0, 400, 10, 420);
  mHits := [Hit(10, 20), Hit(120, 140), Hit(240, 260), Hit(400, 420)];
  mCount := 4;
  mScroll.Shift(mItems, 1, 3, mHits, 1, mCount);
  Assert.AreEqual(10, mItems[0].Rect.Top, 'vor dem Bereich bleibt');
  Assert.AreEqual(70, mItems[1].Rect.Top);
  Assert.AreEqual(350, mItems[2].Rect.Top);
  // 120..140 liegt nach dem Versatz über der Sicht, 240..260 wird auf 190..200 beschnitten, 400 fällt weg.
  Assert.AreEqual(2, mCount);
  Assert.AreEqual(10, mHits[0].Rect.Top);
  Assert.AreEqual(190, mHits[1].Rect.Top);
  Assert.AreEqual(200, mHits[1].Rect.Bottom);
  Assert.AreEqual(1, mScroll.ClipFrom);
  Assert.AreEqual(3, mScroll.ClipTill);
  mItems := nil;
  mHits := nil;
end;

procedure THoverItemsTests.ThumbFollowsScroll;
var
  mScroll: TAtlasHoverScroll;
  mThumb: TRect;
begin
  mScroll := TAtlasHoverScroll.None;
  mScroll.Fit(Request(5, 0, 0), 100, 500, 300, 20);
  mThumb := mScroll.Thumb(16, 7, 3);
  Assert.AreEqual(293, mThumb.Left);
  Assert.AreEqual(297, mThumb.Right);
  Assert.AreEqual(100, mThumb.Top);
  Assert.AreEqual(25, Integer(mThumb.Height), '100 * 100 / 400');
  mScroll.Fit(Request(5, 0, 300), 100, 500, 300, 20);
  mThumb := mScroll.Thumb(16, 7, 3);
  Assert.AreEqual(200, mThumb.Bottom);
  mScroll.Fit(Request(3, 0, 0), 100, 10100, 300, 20);
  Assert.AreEqual(16, Integer(mScroll.Thumb(16, 7, 3).Height), 'Mindesthöhe');
end;

initialization
  TDUnitX.RegisterTestFixture(THoverItemsTests);

end.
