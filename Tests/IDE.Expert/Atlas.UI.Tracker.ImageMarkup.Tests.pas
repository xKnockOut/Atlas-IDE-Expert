unit Atlas.UI.Tracker.ImageMarkup.Tests;

// Markieren vor dem Anhängen (#1276): Rahmen, Pfeil und Schwärzen landen im
// Bild selbst; Rückgängig nimmt die letzte Form; winzige Formen (Klick ohne
// Ziehen) zählen nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasImageMarkupTests = class
  public
    [Test]
    procedure BoundsAndTiny;
    /// <summary>Abnahme: Geschwärzter Bereich ist im Bild schwarz, nicht nur überdeckt.</summary>
    [Test]
    procedure BlackenFillsPixels;
    [Test]
    procedure RectangleAndArrowAreRed;
    [Test]
    procedure FormUndoAndApply;
  end;

implementation

uses
  System.Types,
  Vcl.Graphics,
  Atlas.UI.Tracker.ImageMarkup;

function WhiteBitmap(AWidth, AHeight: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

{ TAtlasImageMarkupTests }

procedure TAtlasImageMarkupTests.BoundsAndTiny;
var
  mShape: TAtlasMarkupShape;
begin
  mShape := TAtlasMarkupShape.Create(TAtlasMarkupTool.Rectangle, Point(40, 30), Point(10, 5));
  Assert.AreEqual(10, mShape.Bounds.Left);
  Assert.AreEqual(5, mShape.Bounds.Top);
  Assert.AreEqual(40, mShape.Bounds.Right);
  Assert.AreEqual(30, mShape.Bounds.Bottom);
  Assert.IsFalse(mShape.Tiny);
  Assert.IsTrue(TAtlasMarkupShape.Create(TAtlasMarkupTool.Arrow, Point(5, 5), Point(6, 7)).Tiny);
  Assert.IsFalse(TAtlasMarkupShape.Create(TAtlasMarkupTool.Arrow, Point(5, 5), Point(5, 20)).Tiny,
    'senkrechter Pfeil');
end;

procedure TAtlasImageMarkupTests.BlackenFillsPixels;
var
  mBitmap: TBitmap;
begin
  mBitmap := WhiteBitmap(60, 40);
  try
    TAtlasImageMarkup.Apply(mBitmap, [TAtlasMarkupShape.Create(TAtlasMarkupTool.Blacken, Point(10, 10),
      Point(30, 20))]);
    Assert.AreEqual(Integer(clBlack), Integer(mBitmap.Canvas.Pixels[15, 15]));
    Assert.AreEqual(Integer(clBlack), Integer(mBitmap.Canvas.Pixels[10, 10]));
    Assert.AreEqual(Integer(clWhite), Integer(mBitmap.Canvas.Pixels[35, 15]));
    Assert.AreEqual(Integer(clWhite), Integer(mBitmap.Canvas.Pixels[15, 25]));
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasImageMarkupTests.RectangleAndArrowAreRed;
var
  mBitmap: TBitmap;
begin
  mBitmap := WhiteBitmap(100, 100);
  try
    TAtlasImageMarkup.Apply(mBitmap, [TAtlasMarkupShape.Create(TAtlasMarkupTool.Rectangle, Point(10, 10),
      Point(40, 40)), TAtlasMarkupShape.Create(TAtlasMarkupTool.Arrow, Point(10, 80), Point(90, 80))]);
    // Rahmen: Kante rot, innen weiß.
    Assert.AreEqual(Integer(clRed), Integer(mBitmap.Canvas.Pixels[10, 25]));
    Assert.AreEqual(Integer(clWhite), Integer(mBitmap.Canvas.Pixels[25, 25]));
    // Pfeil: Linie und Spitze rot.
    Assert.AreEqual(Integer(clRed), Integer(mBitmap.Canvas.Pixels[50, 80]));
    Assert.AreEqual(Integer(clRed), Integer(mBitmap.Canvas.Pixels[85, 80]));
    Assert.AreEqual(Integer(clWhite), Integer(mBitmap.Canvas.Pixels[50, 60]));
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasImageMarkupTests.FormUndoAndApply;
var
  mBitmap: TBitmap;
  mForm: TAtlasImageMarkupForm;
begin
  mBitmap := WhiteBitmap(50, 50);
  try
    mForm := TAtlasImageMarkupForm.CreateFor(nil, mBitmap);
    try
      mForm.AddShape(TAtlasMarkupShape.Create(TAtlasMarkupTool.Blacken, Point(0, 0), Point(20, 20)));
      mForm.AddShape(TAtlasMarkupShape.Create(TAtlasMarkupTool.Blacken, Point(30, 30), Point(50, 50)));
      // Ein Klick ohne Ziehen legt nichts an.
      mForm.AddShape(TAtlasMarkupShape.Create(TAtlasMarkupTool.Rectangle, Point(5, 5), Point(5, 5)));
      Assert.AreEqual(2, Integer(Length(mForm.Shapes)));
      mForm.Undo;
      Assert.AreEqual(1, Integer(Length(mForm.Shapes)));
      // Das Original bleibt bis „Übernehmen“ unverändert.
      Assert.AreEqual(Integer(clWhite), Integer(mBitmap.Canvas.Pixels[10, 10]));
      mForm.ApplyTo(mBitmap);
      Assert.AreEqual(Integer(clBlack), Integer(mBitmap.Canvas.Pixels[10, 10]));
      Assert.AreEqual(Integer(clWhite), Integer(mBitmap.Canvas.Pixels[40, 40]), 'zurückgenommen');
    finally
      mForm.Free;
    end;
  finally
    mBitmap.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasImageMarkupTests);

end.
