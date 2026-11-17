unit Atlas.UI.Foundation.ListBox.Tests;

// Liste ohne Flackern: doppelt gepuffert; WM_ERASEBKGND am Bildschirm löscht
// nichts, das Löschen in den Puffer (wParam = lParam) füllt wie üblich.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Foundation.ListBox;

type
  [TestFixture]
  TAtlasListBoxTests = class
  private
    FForm: TForm;
    FList: TAtlasListBox;
    /// <summary>Farbe eines Bildes in Rot, nachdem die Liste WM_ERASEBKGND mit dessen DC bekommen hat; AIntoBuffer
    /// wie TWinControl.WMPaint beim Zeichnen in den Puffer (wParam = lParam).</summary>
    function ColorAfterErase(AIntoBuffer: Boolean; out AResult: NativeInt): Integer;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure IsDoubleBuffered;
    [Test]
    procedure SkipsEraseOnScreen;
    [Test]
    procedure ErasesIntoBuffer;
    [Test]
    procedure WithoutBufferErasesOnScreen;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Graphics;

{ TAtlasListBoxTests }

procedure TAtlasListBoxTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FList := TAtlasListBox.Create(FForm);
  FList.Parent := FForm;
  FList.Color := clLime;
  FList.HandleNeeded;
end;

procedure TAtlasListBoxTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FList := nil;
end;

function TAtlasListBoxTests.ColorAfterErase(AIntoBuffer: Boolean; out AResult: NativeInt): Integer;
var
  mBitmap: Vcl.Graphics.TBitmap;
  mDC: HDC;
  mLParam: LPARAM;
begin
  mBitmap := Vcl.Graphics.TBitmap.Create;
  try
    mBitmap.SetSize(8, 8);
    mBitmap.Canvas.Brush.Color := clRed;
    mBitmap.Canvas.FillRect(Rect(0, 0, 8, 8));
    mDC := mBitmap.Canvas.Handle;
    mLParam := 0;
    if AIntoBuffer then
    begin
      mLParam := LPARAM(mDC);
    end;
    AResult := FList.Perform(WM_ERASEBKGND, WPARAM(mDC), mLParam);
    Result := ColorToRGB(mBitmap.Canvas.Pixels[1, 1]);
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasListBoxTests.IsDoubleBuffered;
begin
  Assert.IsTrue(FList.DoubleBuffered);
end;

procedure TAtlasListBoxTests.SkipsEraseOnScreen;
var
  mResult: NativeInt;
begin
  // Am Bildschirm (lParam = 0) bleibt die Fläche, wie sie ist; 1 meldet „gelöscht“, damit niemand nachfüllt.
  Assert.AreEqual(Integer(ColorToRGB(clRed)), ColorAfterErase(False, mResult));
  Assert.AreEqual(Integer(1), Integer(mResult));
end;

procedure TAtlasListBoxTests.ErasesIntoBuffer;
var
  mResult: NativeInt;
begin
  // In den Puffer füllt die Liste ihre Farbe (auch die Fläche unter der letzten Zeile).
  Assert.AreEqual(Integer(ColorToRGB(clLime)), ColorAfterErase(True, mResult));
end;

procedure TAtlasListBoxTests.WithoutBufferErasesOnScreen;
var
  mResult: NativeInt;
begin
  FList.DoubleBuffered := False;
  Assert.AreEqual(Integer(ColorToRGB(clLime)), ColorAfterErase(False, mResult));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasListBoxTests);

end.
