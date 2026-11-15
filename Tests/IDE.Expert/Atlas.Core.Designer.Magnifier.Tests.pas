unit Atlas.Core.Designer.Magnifier.Tests;

// Tests der Lupe für den Designer (#743): Umrechnung Bildschirm → DFM-Pixel
// bei 100/125/150/200 %, Stufen, Ausschnitt und Farbnamen.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Designer.Magnifier;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasMagnifierTests = class
  public
    [Test]
    procedure DesignAt100;
    [Test]
    procedure DesignAt125;
    [Test]
    procedure DesignAt150;
    [Test]
    procedure DesignAt200;
    [Test]
    procedure DesignRoundsHalfAway;
    [Test]
    procedure ZoomSteps;
    [Test]
    procedure SourceRectAroundCenter;
    [Test]
    procedure ViewMapping;
    [Test]
    procedure HexAndStandardNames;
    [Test]
    procedure SystemNamesFirstInListOrder;
    [Test]
    procedure RefreshOnlyWhenDue;
    [Test]
    procedure EdgesCrossingSource;
    [Test]
    procedure MenuZoomsAndRgb;
  end;

implementation

const
  cDesignPpi = 96;

{ TAtlasMagnifierTests }

procedure TAtlasMagnifierTests.DesignAt100;
begin
  Assert.AreEqual(120, TAtlasMagnifier.ToDesign(120, 96, cDesignPpi));
  Assert.AreEqual(0, TAtlasMagnifier.ToDesign(0, 96, cDesignPpi));
end;

procedure TAtlasMagnifierTests.DesignAt125;
begin
  Assert.AreEqual(100, TAtlasMagnifier.ToDesign(125, 120, cDesignPpi));
  Assert.AreEqual(8, TAtlasMagnifier.ToDesign(10, 120, cDesignPpi));
end;

procedure TAtlasMagnifierTests.DesignAt150;
begin
  // Left = 100 in der DFM liegt bei 150 % auf Bildschirmpixel 150.
  Assert.AreEqual(100, TAtlasMagnifier.ToDesign(150, 144, cDesignPpi));
  Assert.AreEqual(24, TAtlasMagnifier.ToDesign(36, 144, cDesignPpi));
end;

procedure TAtlasMagnifierTests.DesignAt200;
begin
  Assert.AreEqual(100, TAtlasMagnifier.ToDesign(200, 192, cDesignPpi));
  Assert.AreEqual(1, TAtlasMagnifier.ToDesign(1, 192, cDesignPpi));
end;

procedure TAtlasMagnifierTests.DesignRoundsHalfAway;
begin
  Assert.AreEqual(101, TAtlasMagnifier.ToDesign(151, 144, cDesignPpi));
  Assert.AreEqual(-101, TAtlasMagnifier.ToDesign(-151, 144, cDesignPpi));
  Assert.AreEqual(-100, TAtlasMagnifier.ToDesign(-150, 144, cDesignPpi));
  // Ungültige Skalierung: unverändert.
  Assert.AreEqual(77, TAtlasMagnifier.ToDesign(77, 0, cDesignPpi));
end;

procedure TAtlasMagnifierTests.ZoomSteps;
begin
  Assert.AreEqual(4, TAtlasMagnifier.NormalizeZoom(3));
  Assert.AreEqual(8, TAtlasMagnifier.NormalizeZoom(16));
  Assert.AreEqual(2, TAtlasMagnifier.NormalizeZoom(0));
  Assert.AreEqual(8, TAtlasMagnifier.NextZoom(4, 1));
  Assert.AreEqual(8, TAtlasMagnifier.NextZoom(8, 1));
  Assert.AreEqual(2, TAtlasMagnifier.NextZoom(4, -1));
  Assert.AreEqual(2, TAtlasMagnifier.NextZoom(2, -1));
  Assert.AreEqual(4, TAtlasMagnifier.NextZoom(4, 0));
end;

procedure TAtlasMagnifierTests.SourceRectAroundCenter;
var
  mRect: TRect;
begin
  mRect := TAtlasMagnifier.SourceRect(Point(100, 100), TSize.Create(240, 180), 4);
  Assert.AreEqual(70, mRect.Left);
  Assert.AreEqual(78, mRect.Top);
  Assert.AreEqual(60, mRect.Width);
  Assert.AreEqual(45, mRect.Height);
  // Nicht teilbar: aufgerundet, die Ansicht bleibt gefüllt.
  mRect := TAtlasMagnifier.SourceRect(Point(0, 0), TSize.Create(241, 179), 8);
  Assert.AreEqual(31, mRect.Width);
  Assert.AreEqual(23, mRect.Height);
end;

procedure TAtlasMagnifierTests.ViewMapping;
begin
  Assert.AreEqual(0, TAtlasMagnifier.ToView(70, 70, 4));
  Assert.AreEqual(120, TAtlasMagnifier.ToView(100, 70, 4));
  Assert.AreEqual(-8, TAtlasMagnifier.ToView(69, 70, 8));
end;

procedure TAtlasMagnifierTests.HexAndStandardNames;
begin
  Assert.AreEqual('#FFFFFF', TAtlasMagnifier.HexOf($FFFFFF));
  Assert.AreEqual('#0A0B0C', TAtlasMagnifier.HexOf($0A0B0C));
  Assert.AreEqual('clWhite', TAtlasMagnifier.StandardName($FFFFFF));
  Assert.AreEqual('clMoneyGreen', TAtlasMagnifier.StandardName($C0DCC0));
  Assert.AreEqual('clMaroon', TAtlasMagnifier.StandardName($800000));
  Assert.AreEqual('', TAtlasMagnifier.StandardName($123456));
end;

procedure TAtlasMagnifierTests.SystemNamesFirstInListOrder;
var
  mNames: TArray<string>;
begin
  mNames := TAtlasMagnifier.NamesOf($FFFFFF, [TAtlasNamedColor.Create('clWindow', $FFFFFF),
    TAtlasNamedColor.Create('clBtnFace', $F0F0F0), TAtlasNamedColor.Create('clHighlightText', $FFFFFF)]);
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('clWindow', mNames[0]);
  Assert.AreEqual('clHighlightText', mNames[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasMagnifier.NamesOf($010203, [TAtlasNamedColor.Create('clWindow',
    $FFFFFF)]))));
end;

procedure TAtlasMagnifierTests.RefreshOnlyWhenDue;
begin
  Assert.IsTrue(TAtlasMagnifier.RefreshDue(True, False, 1000, 1000), 'erzwungen');
  Assert.IsTrue(TAtlasMagnifier.RefreshDue(False, True, 1000, 1000), 'Maus bewegt');
  Assert.IsFalse(TAtlasMagnifier.RefreshDue(False, False, 1000 + TAtlasMagnifier.cRefreshMs - 1, 1000));
  Assert.IsTrue(TAtlasMagnifier.RefreshDue(False, False, 1000 + TAtlasMagnifier.cRefreshMs, 1000));
end;

procedure TAtlasMagnifierTests.EdgesCrossingSource;
var
  mSource: TRect;
begin
  mSource := Rect(100, 100, 140, 130);
  Assert.IsTrue(TAtlasMagnifier.Crosses(Rect(90, 90, 110, 110), mSource), 'überlappt');
  Assert.IsTrue(TAtlasMagnifier.Crosses(Rect(140, 100, 150, 110), mSource), 'linke Kante auf rechtem Rand');
  Assert.IsFalse(TAtlasMagnifier.Crosses(Rect(141, 100, 150, 110), mSource), 'rechts daneben');
  Assert.IsFalse(TAtlasMagnifier.Crosses(Rect(100, 50, 140, 99), mSource), 'darüber');
end;

procedure TAtlasMagnifierTests.MenuZoomsAndRgb;
var
  mZooms: TArray<Integer>;
begin
  mZooms := TAtlasMagnifier.Zooms;
  Assert.AreEqual(3, Integer(Length(mZooms)));
  Assert.AreEqual(2, mZooms[0]);
  Assert.AreEqual(4, mZooms[1]);
  Assert.AreEqual(8, mZooms[2]);
  Assert.AreEqual(Cardinal($123456), TAtlasMagnifier.RgbOf($12, $34, $56));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMagnifierTests);

end.
