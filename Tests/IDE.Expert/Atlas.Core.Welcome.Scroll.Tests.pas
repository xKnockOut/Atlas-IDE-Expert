unit Atlas.Core.Welcome.Scroll.Tests;

// Tests der Scrollschritte der Willkommensseite ohne VCL (#1440): Grenzen,
// Mausrad in Pixeln und Zeilen (auch feine Räder und Seitenmodus), Tasten und
// Scrollen am Rand beim Ziehen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeScrollTests = class
  public
    [Test]
    procedure MaxAndClampStayInRange;
    [Test]
    procedure CanScrollFollowsDirection;
    [Test]
    procedure WheelPixelsFollowLines;
    [Test]
    procedure FineWheelCollectsRest;
    [Test]
    procedure PageModeScrollsOnePage;
    [Test]
    procedure WheelLinesForLists;
    [Test]
    procedure KeysMoveByPageAndToEnds;
    [Test]
    procedure EdgeScrollsNearBorders;
  end;

implementation

uses
  Atlas.Core.Welcome.Scroll;

{ TAtlasWelcomeScrollTests }

procedure TAtlasWelcomeScrollTests.MaxAndClampStayInRange;
begin
  Assert.AreEqual(400, TAtlasWelcomeScroll.MaxPosition(1000, 600));
  Assert.AreEqual(0, TAtlasWelcomeScroll.MaxPosition(300, 600), 'passt alles, gibt es nichts zu scrollen');
  Assert.AreEqual(0, TAtlasWelcomeScroll.Clamp(-5, 400));
  Assert.AreEqual(400, TAtlasWelcomeScroll.Clamp(450, 400));
  Assert.AreEqual(120, TAtlasWelcomeScroll.Clamp(120, 400));
  Assert.AreEqual(0, TAtlasWelcomeScroll.Clamp(10, 0));
end;

procedure TAtlasWelcomeScrollTests.CanScrollFollowsDirection;
begin
  // Positives Delta = Rad nach oben.
  Assert.IsFalse(TAtlasWelcomeScroll.CanScroll(0, 400, 120), 'oben am Anfang');
  Assert.IsTrue(TAtlasWelcomeScroll.CanScroll(0, 400, -120));
  Assert.IsTrue(TAtlasWelcomeScroll.CanScroll(400, 400, 120));
  Assert.IsFalse(TAtlasWelcomeScroll.CanScroll(400, 400, -120), 'unten am Ende');
  Assert.IsFalse(TAtlasWelcomeScroll.CanScroll(0, 0, -120), 'ohne Überlänge');
  Assert.IsFalse(TAtlasWelcomeScroll.CanScroll(10, 400, 0));
end;

procedure TAtlasWelcomeScrollTests.WheelPixelsFollowLines;
var
  mRest: Integer;
begin
  mRest := 0;
  // Ein Raster nach unten, 3 Zeilen zu 20 Pixeln.
  Assert.AreEqual(60, TAtlasWelcomeScroll.WheelPixels(mRest, -120, 3, 20, 500));
  Assert.AreEqual(0, mRest);
  Assert.AreEqual(-60, TAtlasWelcomeScroll.WheelPixels(mRest, 120, 3, 20, 500));
  Assert.AreEqual(-120, TAtlasWelcomeScroll.WheelPixels(mRest, 240, 3, 20, 500), 'zwei Raster');
  Assert.AreEqual(0, mRest);
end;

procedure TAtlasWelcomeScrollTests.FineWheelCollectsRest;
var
  mRest, mSum, mIndex: Integer;
begin
  mRest := 0;
  mSum := 0;
  // Touchpad: zwölf Schritte zu 10 ergeben zusammen ein Raster.
  for mIndex := 1 to 12 do
    Inc(mSum, TAtlasWelcomeScroll.WheelPixels(mRest, -10, 3, 20, 500));
  Assert.AreEqual(60, mSum);
  Assert.AreEqual(0, mRest);
  // Ein Rest der alten Richtung zählt nach einem Richtungswechsel nicht mit.
  mRest := 0;
  TAtlasWelcomeScroll.WheelPixels(mRest, -1, 3, 20, 500);
  Assert.AreEqual(-1, mRest);
  Assert.AreEqual(-60, TAtlasWelcomeScroll.WheelPixels(mRest, 120, 3, 20, 500));
  Assert.AreEqual(0, mRest);
end;

procedure TAtlasWelcomeScrollTests.PageModeScrollsOnePage;
var
  mRest: Integer;
begin
  mRest := 0;
  // WHEEL_PAGESCROLL kommt als sehr große bzw. negative Zeilenzahl.
  Assert.AreEqual(500, TAtlasWelcomeScroll.WheelPixels(mRest, -120, -1, 20, 500));
  Assert.AreEqual(-500, TAtlasWelcomeScroll.WheelPixels(mRest, 120, 1000, 20, 500));
  Assert.AreEqual(1, TAtlasWelcomeScroll.WheelPixels(mRest, -120, 0, 20, 0), 'ohne Fläche wenigstens ein Pixel');
end;

procedure TAtlasWelcomeScrollTests.WheelLinesForLists;
var
  mRest: Integer;
begin
  mRest := 0;
  Assert.AreEqual(3, TAtlasWelcomeScroll.WheelLines(mRest, -120, 3));
  Assert.AreEqual(-3, TAtlasWelcomeScroll.WheelLines(mRest, 120, 3));
  Assert.AreEqual(0, TAtlasWelcomeScroll.WheelLines(mRest, -30, 3), 'Bruchteil einer Zeile');
  Assert.AreEqual(-30, mRest);
  Assert.AreEqual(1, TAtlasWelcomeScroll.WheelLines(mRest, -10, 3), 'Rest ergibt eine Zeile');
  Assert.AreEqual(0, mRest);
  Assert.AreEqual(3, TAtlasWelcomeScroll.WheelLines(mRest, -120, -1), 'Seitenmodus: drei Zeilen');
end;

procedure TAtlasWelcomeScrollTests.KeysMoveByPageAndToEnds;
begin
  // Seite 300, Zeile 20: Bild ab um 280 (eine Zeile Überlappung).
  Assert.AreEqual(380, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.PageDown, 100, 1000, 300, 20));
  Assert.AreEqual(0, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.PageUp, 100, 1000, 300, 20));
  Assert.AreEqual(1000, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.PageDown, 900, 1000, 300, 20));
  Assert.AreEqual(0, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.Top, 640, 1000, 300, 20));
  Assert.AreEqual(1000, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.Bottom, 640, 1000, 300, 20));
  Assert.AreEqual(640, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.None, 640, 1000, 300, 20));
  // Sehr niedrige Fläche: wenigstens eine Zeile.
  Assert.AreEqual(120, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.PageDown, 100, 1000, 10, 20));
  Assert.AreEqual(0, TAtlasWelcomeScroll.KeyPosition(TAtlasWelcomeScrollKey.Bottom, 0, 0, 300, 20),
    'ohne Überlänge bleibt alles stehen');
end;

procedure TAtlasWelcomeScrollTests.EdgeScrollsNearBorders;
begin
  // Fläche 300 hoch, Randstreifen 32, größter Schritt 24.
  Assert.AreEqual(0, TAtlasWelcomeScroll.EdgeScroll(150, 300, 32, 24), 'Mitte');
  Assert.AreEqual(-24, TAtlasWelcomeScroll.EdgeScroll(0, 300, 32, 24), 'ganz oben');
  Assert.AreEqual(-1, TAtlasWelcomeScroll.EdgeScroll(31, 300, 32, 24), 'Innenkante oben');
  Assert.AreEqual(0, TAtlasWelcomeScroll.EdgeScroll(32, 300, 32, 24));
  Assert.AreEqual(24, TAtlasWelcomeScroll.EdgeScroll(299, 300, 32, 24), 'ganz unten');
  Assert.AreEqual(1, TAtlasWelcomeScroll.EdgeScroll(268, 300, 32, 24), 'Innenkante unten');
  Assert.AreEqual(0, TAtlasWelcomeScroll.EdgeScroll(267, 300, 32, 24));
  Assert.AreEqual(-24, TAtlasWelcomeScroll.EdgeScroll(-5, 300, 32, 24), 'über der Fläche');
  Assert.AreEqual(24, TAtlasWelcomeScroll.EdgeScroll(300, 300, 32, 24), 'unter der Fläche');
  // Niedrige Fläche: Randstreifen höchstens ein Drittel, die Mitte bleibt ruhig.
  Assert.AreEqual(0, TAtlasWelcomeScroll.EdgeScroll(30, 60, 32, 24));
  Assert.IsTrue(TAtlasWelcomeScroll.EdgeScroll(5, 60, 32, 24) < 0);
  Assert.AreEqual(0, TAtlasWelcomeScroll.EdgeScroll(10, 0, 32, 24), 'ohne Höhe');
end;

end.
