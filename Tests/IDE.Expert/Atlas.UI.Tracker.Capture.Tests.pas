unit Atlas.UI.Tracker.Capture.Tests;

// Bilder für „An Issue anhängen“ (#1276): Verkleinern auf
// issues.attach.maxImageWidth, PNG hin und zurück, ungültige PNG-Daten,
// Bilder untereinander für die Zwischenablage (GitHub) und die Fensterliste
// eines Prozesses ohne Fenster. Das Aufnehmen selbst braucht ein echtes
// Fenster und steht in den Handtests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasAttachImagesTests = class
  public
    /// <summary>Abnahme: Ein Bild über der Höchstbreite wird mit Seitenverhältnis verkleinert.</summary>
    [Test]
    procedure ScaledKeepsAspect;
    [Test]
    procedure SmallImageStays;
    [Test]
    procedure PngRoundTrip;
    [Test]
    procedure InvalidPngIsNil;
    [Test]
    procedure StackedOneBelowTheOther;
    [Test]
    procedure NoWindowsWithoutProcess;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.UI.Tracker.Capture;

function Filled(AWidth, AHeight: Integer; AColor: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := AColor;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

{ TAtlasAttachImagesTests }

procedure TAtlasAttachImagesTests.ScaledKeepsAspect;
var
  mSource, mScaled: TBitmap;
begin
  mSource := Filled(2560, 1440, clBlue);
  try
    mScaled := TAtlasAttachImages.Scaled(mSource, 1920);
    try
      Assert.AreEqual(1920, mScaled.Width);
      Assert.AreEqual(1080, mScaled.Height);
      Assert.AreEqual(Integer(clBlue), Integer(mScaled.Canvas.Pixels[960, 540]));
    finally
      mScaled.Free;
    end;
  finally
    mSource.Free;
  end;
end;

procedure TAtlasAttachImagesTests.SmallImageStays;
var
  mSource, mScaled: TBitmap;
begin
  mSource := Filled(800, 600, clRed);
  try
    mScaled := TAtlasAttachImages.Scaled(mSource, 1920);
    try
      Assert.IsTrue(Pointer(mSource) <> Pointer(mScaled), 'immer eine Kopie');
      Assert.AreEqual(800, mScaled.Width);
      Assert.AreEqual(600, mScaled.Height);
    finally
      mScaled.Free;
    end;
  finally
    mSource.Free;
  end;
end;

procedure TAtlasAttachImagesTests.PngRoundTrip;
var
  mSource, mBack: TBitmap;
  mBytes: TBytes;
begin
  mSource := Filled(40, 20, clGreen);
  try
    mSource.Canvas.Pixels[5, 5] := clBlack;
    mBytes := TAtlasAttachImages.PngBytes(mSource);
    // PNG-Signatur.
    Assert.IsTrue(Length(mBytes) > 8);
    Assert.AreEqual(137, Integer(mBytes[0]));
    Assert.AreEqual(Ord('P'), Integer(mBytes[1]));
    mBack := TAtlasAttachImages.FromPng(mBytes);
    try
      Assert.IsNotNull(mBack);
      Assert.AreEqual(40, mBack.Width);
      Assert.AreEqual(20, mBack.Height);
      Assert.AreEqual(Integer(clBlack), Integer(mBack.Canvas.Pixels[5, 5]));
      Assert.AreEqual(Integer(clGreen), Integer(mBack.Canvas.Pixels[20, 10]));
    finally
      mBack.Free;
    end;
  finally
    mSource.Free;
  end;
end;

procedure TAtlasAttachImagesTests.InvalidPngIsNil;
begin
  Assert.IsNull(TAtlasAttachImages.FromPng(TEncoding.ASCII.GetBytes('kein Bild')));
  Assert.IsNull(TAtlasAttachImages.FromPng(nil));
end;

procedure TAtlasAttachImagesTests.StackedOneBelowTheOther;
var
  mTop, mBottom, mStacked: TBitmap;
begin
  mTop := Filled(100, 30, clRed);
  mBottom := Filled(60, 20, clBlue);
  try
    mStacked := TAtlasAttachImages.Stacked([mTop, mBottom], 10);
    try
      Assert.AreEqual(100, mStacked.Width);
      Assert.AreEqual(60, mStacked.Height);
      Assert.AreEqual(Integer(clRed), Integer(mStacked.Canvas.Pixels[50, 15]));
      Assert.AreEqual(Integer(clWhite), Integer(mStacked.Canvas.Pixels[50, 35]), 'Abstand');
      Assert.AreEqual(Integer(clBlue), Integer(mStacked.Canvas.Pixels[30, 50]));
      Assert.AreEqual(Integer(clWhite), Integer(mStacked.Canvas.Pixels[80, 50]), 'rechts vom schmaleren');
    finally
      mStacked.Free;
    end;
    Assert.IsNull(TAtlasAttachImages.Stacked(nil, 10));
  finally
    mTop.Free;
    mBottom.Free;
  end;
end;

procedure TAtlasAttachImagesTests.NoWindowsWithoutProcess;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasWindowCapture.WindowsOf(0))));
  Assert.IsNull(TAtlasWindowCapture.Capture(0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAttachImagesTests);

end.
